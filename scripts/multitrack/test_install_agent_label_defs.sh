#!/usr/bin/env bash
# =============================================================================
# test_install_agent_label_defs.sh — hermetic tests for
#   scripts/multitrack/install_agent_label_defs.sh and its wiring into
#   scripts/post_update_hook.sh (§11.4.164 seam), §11.4.182 / §11.4.231(F).
#
# Purpose : prove the installer derives the track->branch set from the
#   consumer's config/multitrack/<host>.yaml (with git-HEAD resolution for glob
#   branch patterns), writes the generated label definitions into
#   <project>/.claude/agents, is idempotent, never touches hand-made agents,
#   prunes only genuine generated files of no-longer-configured tracks, and that
#   the constitution post-update hook regenerates them on every pull.
# Usage   : bash scripts/multitrack/test_install_agent_label_defs.sh
# Side-effects: temp dir under ${TMPDIR:-/tmp}, removed on exit. No network.
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.164, §11.4.224(A).
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONST="$(cd "$HERE/../.." && pwd -P)"
INST="$HERE/install_agent_label_defs.sh"
GEN="$HERE/gen_agent_label_defs.sh"
CHK="$HERE/agent_label_frontmatter_check.py"
W="$(mktemp -d "${TMPDIR:-/tmp}/install_agent_label_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2' got '$3'"; fi; }
tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1); }

# ---- fixture project ---------------------------------------------------------------
mkproj() { # dir  -> project with config + track mounts
  local d="$1"
  mkdir -p "$d/config/multitrack" "$d/mnt/track1" "$d/mnt/track2"
  git -C "$d" init -q -b main 2>/dev/null
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$d/mnt/track2" init -q -b feature/zeta 2>/dev/null
  git -C "$d/mnt/track2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cat >"$d/config/multitrack/fixturehost.yaml" <<YAML
schema_version: 1
host:
  hostname: fixturehost
protected_drives:
  - serial: "PROT"
tracks:
  - id: track-1
    role: main
    branch: main
    drive_serial: "A"
    mount: $d/mnt/track1
  - id: track-2
    role: feature
    branch_pattern: "feature/*"
    drive_serial: "B"
    mount: $d/mnt/track2
  - id: track-3
    role: feature
    branch_pattern: "feature/*"
    drive_serial: "C"
    mount: $d/mnt/track3-absent
YAML
}
export MT_HOST=fixturehost
run() { # args... -> exit code; stdout/stderr to $W/out,$W/err
  MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" "$@" >"$W/out" 2>"$W/err"; echo $?
}

echo "install_agent_label_defs.sh test suite"
P="$W/proj"; mkproj "$P"
AG="$P/.claude/agents"

# I01 install -------------------------------------------------------------------------
check "I01a install exit 0" 0 "$(run)"
names=$(ls "$AG" 2>/dev/null | sed 's/-\(sonnet\|opus\)-.*//' | sort -u | tr '\n' ' ')
check "I01b prefixes = T1-main + T2-feature-zeta only (T3 unresolved)" "T1-main T2-feature-zeta " "$names"
check "I01c 20 files (2 tracks x 10)" 20 "$(ls "$AG" 2>/dev/null | wc -l)"
if python3 -I "$CHK" "$AG"/*.md >"$W/chk" 2>&1; then ok "I01d all files pass the strict parser"; else bad "I01d all files pass the strict parser" "$(head -2 "$W/chk")"; fi
grep -q 'track-3' "$W/out" "$W/err" && ok "I01e T3 skip is reported (not silent)" || bad "I01e T3 skip is reported (not silent)"
grep -q '^color: green$' "$AG/T2-feature-zeta-opus-low.md" && ok "I01f T2 colour green" || bad "I01f T2 colour green"

# I02 idempotent ------------------------------------------------------------------------
h1=$(tree_hash "$AG"); check "I02a rerun exit 0" 0 "$(run)"; check "I02b byte-identical" "$h1" "$(tree_hash "$AG")"
grep -q 'written=0' "$W/out" && ok "I02c rerun reports written=0" || bad "I02c rerun reports written=0" "$(tail -2 "$W/out")"

# I03 hand-made agents untouched --------------------------------------------------------
printf -- '---\nname: myagent\ndescription: "mine"\n---\nhand\n' >"$AG/myagent.md"
rm "$AG/T1-main-sonnet-medium.md"
printf -- '---\nname: T1-main-sonnet-medium\ndescription: "hand made"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nHAND\n' >"$AG/T1-main-sonnet-medium.md"
hm1=$(sha256sum "$AG/T1-main-sonnet-medium.md" "$AG/myagent.md")
check "I03a hand-made colliding file -> exit 3" 3 "$(run)"
check "I03b hand-made files byte-unchanged" "$hm1" "$(sha256sum "$AG/T1-main-sonnet-medium.md" "$AG/myagent.md")"
grep -q 'T1-main-sonnet-medium' "$W/err" && ok "I03c refusal names the colliding file" || bad "I03c refusal names the colliding file"
[ -f "$AG/T2-feature-zeta-opus-low.md" ] && ok "I03d other tracks still installed despite one refusal" || bad "I03d other tracks still installed"
rm "$AG/T1-main-sonnet-medium.md"; check "I03e after removing the collision, install heals" 0 "$(run)"

# I04 --check ---------------------------------------------------------------------------
check "I04a --check clean -> 0" 0 "$(run --check)"
rm "$AG/T2-feature-zeta-opus-max.md"; check "I04b --check missing -> 1" 1 "$(run --check)"
[ ! -f "$AG/T2-feature-zeta-opus-max.md" ] && ok "I04c --check wrote nothing" || bad "I04c --check wrote nothing"
run >/dev/null
sed -i 's/^color: blue$/color: red/' "$AG/T1-main-opus-low.md"; check "I04d --check hand-edited generated -> 1" 1 "$(run --check)"
check "I04e install refuses hand-edited generated -> 4" 4 "$(run)"
bash "$GEN" --track 1 --branch main --out-dir "$W/fresh" --models opus --efforts low >/dev/null; cp "$W/fresh/T1-main-opus-low.md" "$AG/"
check "I04f restored -> --check 0" 0 "$(run --check)"

# I05 prune only genuine stale generated -------------------------------------------------
bash "$GEN" --track 9 --branch gone --out-dir "$AG" --models sonnet --efforts low >/dev/null
printf -- '---\nname: T9-handmade\ndescription: "h"\n---\nhand\n' >"$AG/T9-handmade.md"
printf -- '---\nname: T9-legacy-opus-high\ndescription: "hand made, generator-shaped name"\nmodel: opus\neffort: high\ncolor: red\n---\nhand\n' >"$AG/T9-legacy-opus-high.md"
check "I05a --check flags the stale generated file -> 1" 1 "$(run --check)"
check "I05b install exit 0" 0 "$(run)"
[ ! -e "$AG/T9-gone-sonnet-low.md" ] && ok "I05c stale GENERATED file pruned" || bad "I05c stale GENERATED file pruned"
[ -e "$AG/T9-handmade.md" ] && ok "I05d hand-made T9-handmade.md kept" || bad "I05d hand-made T9-handmade.md kept"
[ -e "$AG/T9-legacy-opus-high.md" ] && ok "I05f hand-made file with a GENERATOR-SHAPED name kept (not pruned)" || bad "I05f hand-made generator-shaped file kept"
bash "$GEN" --track 9 --branch gone --out-dir "$AG" --models sonnet --efforts low >/dev/null
check "I05e --no-prune keeps stale" 1 "$(run --no-prune --check >/dev/null; [ -e "$AG/T9-gone-sonnet-low.md" ] && echo 1 || echo 0)"
rm -f "$AG/T9-gone-sonnet-low.md"

# I06 dry-run -----------------------------------------------------------------------------
rm -rf "$W/p2"; mkproj "$W/p2"; P="$W/p2"; check "I06a dry-run exit 0" 0 "$(run --dry-run)"
[ ! -e "$P/.claude" ] && ok "I06b dry-run writes nothing" || bad "I06b dry-run writes nothing"
P="$W/proj"

# I07 config-less project: current checkout only ------------------------------------------
rm -rf "$W/p3"; mkdir -p "$W/p3"; git -C "$W/p3" init -q -b main; git -C "$W/p3" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
MT_HOST=nohost MT_CONFIG_DIR="$W/p3/config/multitrack" bash "$INST" --project-root "$W/p3" >"$W/out" 2>"$W/err"; rc=$?
check "I07a config-less exit 0" 0 "$rc"
check "I07b config-less -> current checkout T1/main (10 files)" 10 "$(find "$W/p3/.claude/agents" -maxdepth 1 -name 'T1-main-*' 2>/dev/null | wc -l)"

# I08 explicit --out-dir + --models/--efforts passthrough ----------------------------------
rm -rf "$W/o"; check "I08a custom out-dir/models/efforts" 0 "$(run --out-dir "$W/o" --models opus --efforts xhigh,max)"
check "I08b 2 files per track = 4" 4 "$(ls "$W/o" | wc -l)"
check "I08c usage: unknown flag -> 2" 2 "$(run --bogus)"

# I09 hook wiring (hermetic fixture constitution) ------------------------------------------------
FC="$W/fakeconst"; mkdir -p "$FC/scripts/multitrack"
printf 'stub\n' >"$FC/Constitution.md"
cp "$CONST/scripts/post_update_hook.sh" "$FC/scripts/"
cp "$HERE/multitrack_config.sh" "$HERE/track_branch_label.sh" "$HERE/gen_agent_label_defs.sh" "$HERE/install_agent_label_defs.sh" "$HERE/agent_label_colors.tsv" "$HERE/agent_label_frontmatter_check.py" "$FC/scripts/multitrack/"
git -C "$FC" init -q -b main; git -C "$FC" add -A; git -C "$FC" -c user.email=t@t -c user.name=t commit -q -m c
rm -rf "$W/hp"; mkproj "$W/hp"; HP="$W/hp"
hookrun() { (cd "$HP" && MT_HOST=fixturehost MT_CONFIG_DIR="$HP/config/multitrack" CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"; echo $?); }
check "I09a hook exit 0 on a no-change pull" 0 "$(hookrun)"
check "I09b hook generated 20 label definitions" 20 "$(ls "$HP/.claude/agents" 2>/dev/null | wc -l)"
hh=$(tree_hash "$HP/.claude/agents"); hookrun >/dev/null; check "I09c hook rerun idempotent" "$hh" "$(tree_hash "$HP/.claude/agents")"
printf -- '---\nname: T1-main-opus-low\ndescription: "hand"\n---\nH\n' >"$W/hand.md"; cp "$W/hand.md" "$HP/.claude/agents/T1-main-opus-low.md"
check "I09d hook is NON-fatal when a hand-made file collides" 0 "$(hookrun)"
cmp -s "$W/hand.md" "$HP/.claude/agents/T1-main-opus-low.md" && ok "I09e hook left the hand-made file alone" || bad "I09e hook left the hand-made file alone"
grep -qi 'hand-made\|label definitions' "$W/hout" "$W/herr" && ok "I09f hook reports the collision as a warning" || bad "I09f hook reports the collision as a warning"
rm "$FC/scripts/multitrack/install_agent_label_defs.sh"; check "I09g hook non-fatal when installer is missing" 0 "$(hookrun)"
grep -qi 'install_agent_label_defs' "$W/hout" "$W/herr" && ok "I09h missing installer reported, not silent" || bad "I09h missing installer reported, not silent"

# I10 lint -------------------------------------------------------------------------------------
bash -n "$INST" 2>/dev/null && ok "I10a bash -n clean" || bad "I10a bash -n clean"
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash "$INST" >"$W/sc" 2>&1 && ok "I10b shellcheck clean" || bad "I10b shellcheck clean" "$(head -3 "$W/sc")"; else ok "I10b shellcheck unavailable (SKIP-with-reason)"; fi
bash -n "$CONST/scripts/post_update_hook.sh" 2>/dev/null && ok "I10c post_update_hook.sh bash -n clean" || bad "I10c post_update_hook.sh bash -n clean"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
