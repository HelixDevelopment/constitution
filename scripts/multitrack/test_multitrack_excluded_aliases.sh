#!/usr/bin/env bash
# =============================================================================
# test_multitrack_excluded_aliases.sh — ATM-834 machine-readable
#                                       `excluded_aliases:` engine key.
# -----------------------------------------------------------------------------
# Purpose:
#   The engine previously read exactly ONE machine-readable alias-policy scalar
#   (`conductor:`). A consumer whose policy excludes FURTHER aliases could state
#   that only in PROSE COMMENTS, which the engine cannot read — so an
#   alias documented as excluded was still positionally mapped onto a track
#   (§11.4.187(4) violation; §11.4.6 — policy must be READ, never inferred).
#
#   This suite proves the additive fix:
#     (A) ZERO CHANGE when the key is absent — the load-bearing compatibility
#         requirement. Every existing config must resolve byte-identically.
#     (B) The parser accepts the real YAML shapes (flow / bare list / block),
#         strips quotes + trailing comments, and matches WHOLE aliases only
#         (§11.4.201(7)(a): `claude1` must not be excluded because `claude10`
#         is listed — the carrier-vs-thing trap).
#     (C) An excluded alias resolves to STAY-HOME (rc 10) exactly like the
#         conductor, AND is filtered out of the positional map so it does not
#         shift every later alias onto the wrong track.
#     (D) §1.1 paired mutation: dropping the exclusion filter from the
#         positional list re-introduces the off-by-one — proving the filter is
#         load-bearing, not decorative.
#
# Usage:   test_multitrack_excluded_aliases.sh
# Inputs (env): none. Hermetic — fixtures + config live under a fresh mktemp -d.
# Outputs: per-case PASS/FAIL lines; exit 0 iff every case passed.
# Side-effects: writes ONLY under its own temp dir (removed on exit, §11.4.14).
# Dependencies: bash, awk, mktemp.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_config.sh            (parser)
#   constitution/scripts/multitrack/multitrack_resolve_worktree.sh  (consumer)
#   docs/research/multitrack_duplicate_supervisors_20260722/DIAGNOSIS.md
#
# Constitution: §11.4.187(4) §11.4.6 §11.4.201(7)(a) §11.4.28 §11.4.67 §1.1
# =============================================================================
set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM

. "$SELF_DIR/multitrack_config.sh" >/dev/null 2>&1 || { echo "cannot source multitrack_config.sh"; exit 1; }

echo "=== ATM-834 excluded_aliases — engine: $SELF_DIR"
echo "--- A. parser (mt_config_excluded_aliases)"

_mk() { printf '%s\n' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }
_expect() {  # $1 label  $2 cfg-path  $3 expected (newline-joined, may be empty)
    local got; got="$(mt_config_excluded_aliases "$2" 2>/dev/null)"
    [ "$got" = "$3" ] && ok "$1" || bad "$1" "expected [$3] got [$got]"
}

_expect "P1 absent key -> EMPTY (zero-change compatibility)" \
    "$(_mk absent.yaml 'conductor: claude1
worktree_subdir: project')" ""

_expect "P2 flow sequence [a, b]" \
    "$(_mk flow.yaml 'conductor: claude1
excluded_aliases: [claude3, claude4]')" "claude3
claude4"

_expect "P3 bare comma list" \
    "$(_mk bare.yaml 'excluded_aliases: claude3, claude4')" "claude3
claude4"

_expect "P4 block sequence" \
    "$(_mk block.yaml 'excluded_aliases:
  - claude3
  - claude4
conductor: claude1')" "claude3
claude4"

_expect "P5 quotes + trailing comment stripped" \
    "$(_mk quoted.yaml 'excluded_aliases: ["claude3", '"'"'claude4'"'"']   # DEAD + operator-excluded')" "claude3
claude4"

_expect "P6 empty flow sequence -> EMPTY" \
    "$(_mk empty.yaml 'excluded_aliases: []')" ""

_expect "P7 block list stops at the next top-level key" \
    "$(_mk stop.yaml 'excluded_aliases:
  - claude3
conductor: claude1
worktree_subdir: project')" "claude3"

echo "--- B. resolver wiring"

# Minimal config: 4 native aliases, 3 feature tracks + 1 main track.
CFG="$TMP/host.yaml"
cat > "$CFG" <<'YAML'
conductor: claude1
worktree_subdir: project
aliases:
  - name: claude1
    kind: native
  - name: claude2
    kind: native
  - name: claude3
    kind: native
  - name: claude4
    kind: native
YAML

# Source the resolver for its functions. `main` runs with no args -> prints
# usage + returns 2; the FUNCTIONS are defined regardless, which is all we need.
# shellcheck disable=SC1090
. "$SELF_DIR/multitrack_resolve_worktree.sh" >/dev/null 2>&1 || true

# Test seam: pin the config + track table instead of host discovery. Everything
# under test (_mrw_alias_excluded / _mrw_eligible_native_aliases /
# _mrw_default_track_for_alias / _mrw_pick) is the REAL shipped code.
MRW_CFG="$CFG"
MRW_BIND="$TMP/no-such-bindings.snapshot"
MRW_WT_SUBDIR="project"
MT_TRACK_COUNT=4
MT_TRACK_1_ID="track-1"; MT_TRACK_1_ROLE="main";    MT_TRACK_1_MOUNT="$TMP/m1"
MT_TRACK_2_ID="track-2"; MT_TRACK_2_ROLE="feature"; MT_TRACK_2_MOUNT="$TMP/m2"
MT_TRACK_3_ID="track-3"; MT_TRACK_3_ROLE="feature"; MT_TRACK_3_MOUNT="$TMP/m3"
MT_TRACK_4_ID="track-4"; MT_TRACK_4_ROLE="feature"; MT_TRACK_4_MOUNT="$TMP/m4"
_mrw_load_cfg() { return 0; }            # seam: config already pinned above

_track_of() { _mrw_default_track_for_alias "$1" 2>/dev/null | cut -f1; }

# ---- B1 ZERO-CHANGE baseline: no excluded_aliases key -----------------------
if [ "$(_track_of claude2)" = "track-2" ] && \
   [ "$(_track_of claude3)" = "track-3" ] && \
   [ "$(_track_of claude4)" = "track-4" ]; then
    ok "B1 ZERO-CHANGE: key absent -> claude2/3/4 -> track-2/3/4 (identical to pre-change)"
else
    bad "B1 zero-change baseline" "got claude2=$(_track_of claude2) claude3=$(_track_of claude3) claude4=$(_track_of claude4)"
fi

_mrw_pick claude2 >/dev/null 2>&1; rc2=$?
_mrw_pick claude1 >/dev/null 2>&1; rc1=$?
[ "$rc2" = "0" ] && [ "$rc1" = "10" ] \
    && ok "B2 ZERO-CHANGE: conductor still rc=10 (stay-home), a normal alias rc=0" \
    || bad "B2 conductor baseline" "claude1 rc=$rc1 (want 10), claude2 rc=$rc2 (want 0)"

# ---- B3 with excluded_aliases: claude3 --------------------------------------
cat > "$CFG" <<'YAML'
conductor: claude1
excluded_aliases: [claude3]
worktree_subdir: project
aliases:
  - name: claude1
    kind: native
  - name: claude2
    kind: native
  - name: claude3
    kind: native
  - name: claude4
    kind: native
YAML

_mrw_pick claude3 >/dev/null 2>&1; rc3=$?
[ "$rc3" = "10" ] \
    && ok "B3 excluded alias -> rc=10 STAY-HOME (never worktree-bound, like the conductor)" \
    || bad "B3 excluded alias not stay-home" "claude3 rc=$rc3 (want 10)"

if [ "$(_track_of claude2)" = "track-2" ] && [ "$(_track_of claude4)" = "track-3" ]; then
    ok "B4 excluded alias filtered from the positional list -> claude2->track-2, claude4->track-3 (no orphaned slot)"
else
    bad "B4 positional filter" "claude2=$(_track_of claude2) claude4=$(_track_of claude4)"
fi

# ---- B5 whole-alias match, never a substring (§11.4.201(7)(a)) --------------
cat > "$CFG" <<'YAML'
conductor: claudeX
excluded_aliases: [claude10]
aliases:
  - name: claude1
    kind: native
  - name: claude10
    kind: native
YAML
if _mrw_alias_excluded claude10 && ! _mrw_alias_excluded claude1; then
    ok "B5 CARRIER GUARD: 'claude10' excluded does NOT exclude 'claude1' (whole-line match)"
else
    bad "B5 carrier guard" "claude10 excluded=$(_mrw_alias_excluded claude10 && echo yes || echo no); claude1 excluded=$(_mrw_alias_excluded claude1 && echo yes || echo no)"
fi

# ---- MUT §1.1: drop the exclusion filter from the positional list -----------
# SEMANTIC mutation (not a grepped-literal deletion): the eligible-list helper
# stops filtering excluded aliases. B4's off-by-one must reappear.
cat > "$CFG" <<'YAML'
conductor: claude1
excluded_aliases: [claude3]
worktree_subdir: project
aliases:
  - name: claude1
    kind: native
  - name: claude2
    kind: native
  - name: claude3
    kind: native
  - name: claude4
    kind: native
YAML
_mrw_eligible_native_aliases() {          # mutated: conductor filter only
    local cond a
    cond="$(mt_config_conductor "$MRW_CFG" 2>/dev/null || true)"
    _mrw_native_aliases | while IFS= read -r a; do
        [ -n "$a" ] || continue
        [ -n "$cond" ] && [ "$a" = "$cond" ] && continue
        printf '%s\n' "$a"
    done
}
if [ "$(_track_of claude4)" = "track-4" ]; then
    ok "MUT §1.1: filter removed -> claude4 shifts back to track-4 (the off-by-one returns; filter IS load-bearing)"
else
    bad "MUT §1.1: mutation did not change behaviour" "claude4=$(_track_of claude4) — the filter is NOT load-bearing"
fi

echo
echo "--- C. RESULT"
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
