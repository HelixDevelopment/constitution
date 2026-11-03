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
# F10 (review 2026-11-03): with no host config the loader falls back to its BUILT-IN default
# single-track config (mount = the parent of the repo root). That is not a consumer
# declaration, so the installer must not derive tracks from it.
grep -q 'SKIP     track-1' "$W/out" && bad "I07c built-in default config is not used as a declaration" "$(grep 'SKIP' "$W/out")" || ok "I07c built-in default config is not used as a declaration"
grep -q '^NOTE .*current checkout only' "$W/out" && ok "I07d config-less run says it uses the current checkout only" || bad "I07d config-less run says it uses the current checkout only"

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
# consent (review 2026-11-03, F1): without AGENT_LABEL_DEFS_AUTOWIRE=apply the hook only
# reports what it WOULD write (dry-run); `off` skips the step; `apply` writes.
hookrun() { (cd "$HP" && env AGENT_LABEL_DEFS_AUTOWIRE="${AUTOWIRE-apply}" MT_HOST=fixturehost MT_CONFIG_DIR="$HP/config/multitrack" CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"; echo $?); }
hookrun_noenv() { (cd "$HP" && env -u AGENT_LABEL_DEFS_AUTOWIRE MT_HOST=fixturehost MT_CONFIG_DIR="$HP/config/multitrack" CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"; echo $?); }
check "I09j hook default (no consent) exit 0" 0 "$(hookrun_noenv)"
[ ! -e "$HP/.claude" ] && ok "I09k hook default is dry-run: nothing written" || bad "I09k hook default is dry-run: nothing written" "$(ls -R "$HP/.claude" 2>/dev/null | head -3)"
grep -qi 'dry-run' "$W/hout" "$W/herr" && grep -q 'AGENT_LABEL_DEFS_AUTOWIRE=apply' "$W/hout" "$W/herr" && ok "I09l dry-run is reported with the apply switch named" || bad "I09l dry-run is reported with the apply switch named"
check "I09m AUTOWIRE=off exit 0" 0 "$(AUTOWIRE=off hookrun)"
[ ! -e "$HP/.claude" ] && ok "I09n AUTOWIRE=off writes nothing" || bad "I09n AUTOWIRE=off writes nothing"
check "I09o unknown AUTOWIRE value exit 0" 0 "$(AUTOWIRE=bogus hookrun)"
[ ! -e "$HP/.claude" ] && ok "I09p unknown AUTOWIRE value is treated as dry-run" || bad "I09p unknown AUTOWIRE value is treated as dry-run"
check "I09a hook (AUTOWIRE=apply) exit 0 on a no-change pull" 0 "$(hookrun)"
check "I09b hook (AUTOWIRE=apply) generated 20 label definitions" 20 "$(ls "$HP/.claude/agents" 2>/dev/null | wc -l)"
hh=$(tree_hash "$HP/.claude/agents"); hookrun >/dev/null; check "I09c hook rerun idempotent" "$hh" "$(tree_hash "$HP/.claude/agents")"
printf -- '---\nname: T1-main-opus-low\ndescription: "hand"\n---\nH\n' >"$W/hand.md"; cp "$W/hand.md" "$HP/.claude/agents/T1-main-opus-low.md"
check "I09d hook is NON-fatal when a hand-made file collides" 0 "$(hookrun)"
cmp -s "$W/hand.md" "$HP/.claude/agents/T1-main-opus-low.md" && ok "I09e hook left the hand-made file alone" || bad "I09e hook left the hand-made file alone"
grep -qi 'hand-made\|label definitions' "$W/hout" "$W/herr" && ok "I09f hook reports the collision as a warning" || bad "I09f hook reports the collision as a warning"
rm "$FC/scripts/multitrack/install_agent_label_defs.sh"; check "I09g hook non-fatal when installer is missing" 0 "$(hookrun)"
grep -qi 'install_agent_label_defs' "$W/hout" "$W/herr" && ok "I09h missing installer reported, not silent" || bad "I09h missing installer reported, not silent"

# I11 track number normalised (F9): track-007 -> T7, and a rerun prunes nothing -------------------
rm -rf "$W/p7"; mkproj "$W/p7"; sed -i 's/id: track-2$/id: track-007/' "$W/p7/config/multitrack/fixturehost.yaml"
P="$W/p7"; check "I11a track-007 install exit 0" 0 "$(run)"
check "I11b track-007 -> 10 T7-feature-zeta files" 10 "$(ls "$P/.claude/agents" 2>/dev/null | grep -c '^T7-feature-zeta-')"
check "I11c rerun exit 0" 0 "$(run)"; grep -q 'pruned=0' "$W/out" && ok "I11d rerun prunes nothing (T007 and T7 are one track)" || bad "I11d rerun prunes nothing" "$(tail -1 "$W/out")"
# I12 sanitise collision (F9): two branches of one track that map to the same type names ------------
rm -rf "$W/pc"; mkproj "$W/pc"; sed -i 's/^    branch: main$/    branch: Main/' "$W/pc/config/multitrack/fixturehost.yaml"
P="$W/pc"; check "I12a collision install exit 0" 0 "$(run)"
grep -q 'COLLISION' "$W/out" "$W/err" && ok "I12b the sanitise collision is reported" || bad "I12b the sanitise collision is reported" "$(cat "$W/out" "$W/err" | head -5)"
check "I12c one T1-main set only (10 files)" 10 "$(ls "$P/.claude/agents" 2>/dev/null | grep -c '^T1-main-')"
h_c=$(tree_hash "$P/.claude/agents"); run >/dev/null; check "I12d rerun byte-identical (no flip-flop)" "$h_c" "$(tree_hash "$P/.claude/agents")"
grep -q 'written=0' "$W/out" && ok "I12e rerun writes nothing" || bad "I12e rerun writes nothing" "$(tail -1 "$W/out")"
# I13 prune respects the --models/--efforts filter (F4) --------------------------------------------
P="$W/proj"; run >/dev/null
bash "$GEN" --track 9 --branch gone --out-dir "$AG" --models sonnet,opus --efforts low >/dev/null
check "I13a partial run --models sonnet exit 0" 0 "$(run --models sonnet)"
check "I13b declared tracks keep all 10 opus files" 10 "$(ls "$AG" | grep -Ec '^T(1-main|2-feature-zeta)-opus-')"
[ -e "$AG/T1-main-opus-xhigh.md" ] && ok "I13c the opus-xhigh reviewer type survives a --models sonnet run" || bad "I13c the opus-xhigh reviewer type survives a --models sonnet run"
[ -e "$AG/T9-gone-opus-low.md" ] && ok "I13d undeclared track file OUTSIDE the filter (opus) kept" || bad "I13d undeclared track file OUTSIDE the filter (opus) kept"
[ ! -e "$AG/T9-gone-sonnet-low.md" ] && ok "I13e undeclared track file INSIDE the filter (sonnet) pruned" || bad "I13e undeclared track file INSIDE the filter (sonnet) pruned"
check "I13f --efforts low run keeps the declared high files" 0 "$(run --efforts low >/dev/null; ls "$AG" | grep -Ec '^T1-main-(sonnet|opus)-high\.md$' | grep -qx 2 && echo 0 || echo 1)"
check "I13g undeclared opus file pruned by a full run" 0 "$(run >/dev/null; [ ! -e "$AG/T9-gone-opus-low.md" ] && echo 0 || echo 1)"
# I14 refuse a project root / out-dir that is the home dir, an ancestor of it, or a user-level config dir (F1)
# (the HOME cases use --dry-run, so even a broken refusal writes nothing; HOME is never reassigned)
H="${HOME:?HOME must be set for this test}"
check "I14a --project-root \$HOME refused (exit 6)" 6 "$(run --project-root "$H" --dry-run)"
check "I14b --project-root parent of \$HOME refused (exit 6)" 6 "$(run --project-root "$(dirname "$H")" --dry-run)"
check "I14c --project-root / refused (exit 6)" 6 "$(run --project-root / --dry-run)"
check "I14d --out-dir \$HOME/.claude/agents refused (exit 6)" 6 "$(run --out-dir "$H/.claude/agents" --dry-run)"
CP="$W/cfgparent"; mkdir -p "$CP/.claude"; git -C "$CP" init -q -b main; git -C "$CP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
rc=$(CLAUDE_CONFIG_DIR="$CP/.claude" MT_HOST=nohost MT_CONFIG_DIR="$CP/none" bash "$INST" --project-root "$CP" >"$W/out" 2>"$W/err"; echo $?)
check "I14e project whose .claude IS CLAUDE_CONFIG_DIR refused (exit 6)" 6 "$rc"
[ ! -e "$CP/.claude/agents" ] && ok "I14f refused run wrote nothing" || bad "I14f refused run wrote nothing"
grep -qi 'refus' "$W/err" && ok "I14g refusal is explained on stderr" || bad "I14g refusal is explained on stderr"
rc=$(CLAUDE_CONFIG_DIR="$CP/.claude" MT_HOST=nohost MT_CONFIG_DIR="$CP/none" bash "$INST" --project-root "$CP/.claude" >"$W/out" 2>"$W/err"; echo $?)
check "I14h project root equal to CLAUDE_CONFIG_DIR refused (exit 6)" 6 "$rc"
P="$W/proj"; check "I14i an ordinary project still installs (golden-FALSE)" 0 "$(run)"

# I15 round-2 review (R2-1/R2-3): symlinked user config dirs, empty HOME, out-dir containing a user dir
# HOME is given per call as an env prefix pointing into a sandbox; the real HOME is never reassigned.
runh() { # fakehome args... -> exit code (dry-run always; refusal must still be exit 6)
  local fh="$1"; shift
  env -u CLAUDE_CONFIG_DIR HOME="$fh" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run "$@" >"$W/out" 2>"$W/err"; echo $?
}
P="$W/proj"
SH="$W/fakehome"; mkdir -p "$SH/dotreal/agents" "$SH/elsewhere/agents" "$SH/plain"
ln -s "$SH/dotreal" "$SH/.claude"; ln -s "$SH/elsewhere" "$SH/.claude-x"
check "I15a --out-dir ~/.claude/agents (symlinked .claude) refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude/agents")"
check "I15b --project-root ~/.claude (symlink) refused" 6 "$(runh "$SH" --project-root "$SH/.claude")"
check "I15c --project-root = the symlink TARGET refused" 6 "$(runh "$SH" --project-root "$SH/dotreal")"
check "I15d --out-dir inside the symlink TARGET refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/dotreal/agents")"
SP="$W/symproj"; mkdir -p "$SP"; git -C "$SP" init -q -b main; git -C "$SP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
ln -s "$SH/dotreal" "$SP/.claude"
check "I15e project whose .claude links to ~/.claude refused" 6 "$(runh "$SH" --project-root "$SP")"
check "I15f symlinked ~/.claude-x as out-dir parent refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude-x/agents")"
check "I15g relative out-dir into symlinked .claude-x refused" 6 "$(cd "$SH/plain" && runh "$SH" --project-root "$P" --out-dir "../.claude-x/agents")"
# empty HOME: the passwd home is used for the refusal
RH="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
if [ -n "$RH" ] && [ -d "$RH" ]; then
  check "I15h empty HOME: --project-root = passwd home refused" 6 "$(runh "" --project-root "$RH")"
  check "I15i empty HOME: --out-dir ~/.claude/agents (passwd home) refused" 6 "$(runh "" --project-root "$P" --out-dir "$RH/.claude/agents")"
else ok "I15h/i passwd home unavailable (SKIP-with-reason)"; fi
# R2-3 (mutant ME): out-dir that CONTAINS a user config dir (real dirs, no symlinks)
SR="$W/realcfg"; mkdir -p "$SR/proj/.claude/agents"   # user config dir NOT under HOME: only the contains-rule can catch an out-dir above it
rc=$(env CLAUDE_CONFIG_DIR="$SR/proj/.claude" HOME="$SH/plain" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run --project-root "$P" --out-dir "$SR/proj" >"$W/out" 2>"$W/err"; echo $?)
check "I15j --out-dir containing the user config dir refused (exit 6)" 6 "$rc"
grep -q 'contains the user-level' "$W/err" && ok "I15j2 refusal names the contains-rule" || bad "I15j2 refusal names the contains-rule" "$(head -2 "$W/err")"
[ -n "$RH" ] && check "I15l empty HOME: an ordinary project is NOT refused (passwd home resolved, golden-FALSE)" 0 "$(runh "" --project-root "$P")"
check "I15k golden-FALSE: ordinary project under a fake home is not refused" 0 "$(runh "$SH" --project-root "$P")"
# I17 round-3 review (R3-1/R3-6): the filesystem root and system directories are refused (all dry-run)
for od in / // /// /. /.. /./ /../..; do
  check "I17a --out-dir '$od' refused (exit 6)" 6 "$(runh "$SH" --project-root "$P" --out-dir "$od")"
done
for sd in /etc /etc/agents /usr /usr/lib/x /bin /var /root /boot /dev /proc /sys /lib /lib64 /opt /srv /run /home; do
  check "I17b --out-dir '$sd' refused (exit 6)" 6 "$(runh "$SH" --project-root "$P" --out-dir "$sd")"
  [ -d "$sd" ] && check "I17c --project-root '$sd' refused (exit 6)" 6 "$(runh "$SH" --project-root "$sd")"
done
check "I17d golden-FALSE: out-dir under the sandbox (below /tmp-class dirs) not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir "$W/ordinary/agents")"
# consistency: every absolute entry of scripts/lib/protected_paths.list is refused as an out-dir
PPL="$CONST/scripts/lib/protected_paths.list"
if [ -r "$PPL" ]; then
  bad_n=0
  while IFS= read -r e; do
    e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
    case "$e" in /*) ;; *) continue ;; esac
    case "$e" in /tmp|/Users) continue ;; esac   # /tmp is legitimately an ancestor of scratch projects; /Users does not exist on Linux
    r="$(runh "$SH" --project-root "$P" --out-dir "$e")"
    [ "$r" = 6 ] || { bad_n=$((bad_n+1)); echo "    not refused: $e (exit $r)" >&2; }
  done <"$PPL"
  check "I17e every absolute protected_paths.list entry (except /tmp,/Users) is refused as out-dir" 0 "$bad_n"
else bad "I17e protected_paths.list readable"; fi
# R3-2 mutant killers (X3..X7)
ln -s "$W/nonexistent-target" "$SH/.claude-dangling"
check "I18a (X3) out-dir inside a DANGLING ~/.claude-* symlink refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude-dangling/agents")"
check "I18b (X6) out-dir EQUAL to a user config dir (~/.claude-y) refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude-x")"
RHR="$W/realhome"; mkdir -p "$RHR/proj"; ln -s "$RHR" "$W/homelink"
check "I18c (X5) HOME is a symlink: project root = its real target refused" 6 "$(runh "$W/homelink" --project-root "$RHR")"
check "I18d (X5) HOME is a symlink: out-dir = its real target refused" 6 "$(runh "$W/homelink" --project-root "$P" --out-dir "$RHR")"
# X7: HOME empty AND no passwd entry (getent stubbed to fail): refuse, unless --check
STUB="$W/stubbin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 2\n' >"$STUB/getent"; chmod +x "$STUB/getent"
rc=$(env -u CLAUDE_CONFIG_DIR PATH="$STUB:$PATH" HOME="" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run --project-root "$P" >"$W/out" 2>"$W/err"; echo $?)
check "I18e (X7) no resolvable home (HOME empty, getent fails) refused (exit 6)" 6 "$rc"
grep -q 'cannot be resolved' "$W/err" && ok "I18f (X7) refusal explains the unresolvable home" || bad "I18f (X7) refusal explains the unresolvable home"
# X4: track-007 with an absent mount is keyed as T7: its files are kept
P4="$W/p4"; mkdir -p "$P4/config/multitrack"; git -C "$P4" init -q -b main; git -C "$P4" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
cat >"$P4/config/multitrack/fixturehost.yaml" <<YAML
schema_version: 1
host:
  hostname: fixturehost
protected_drives:
  - serial: "PROT"
tracks:
  - id: track-007
    role: feature
    branch_pattern: "feature/*"
    drive_serial: "C"
    mount: $P4/mnt/absent
YAML
bash "$GEN" --track 7 --branch feature/seven --out-dir "$P4/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
MT_HOST=fixturehost MT_CONFIG_DIR="$P4/config/multitrack" bash "$INST" --project-root "$P4" >/dev/null 2>&1
[ -e "$P4/.claude/agents/T7-feature-seven-sonnet-low.md" ] && ok "I18g (X4) track-007 with absent mount: T7 files kept (keyed as 7)" || bad "I18g (X4) track-007 with absent mount: T7 files kept"
# R2-2: a declared track whose mount is absent / host mismatched must NOT have its files pruned
P="$W/proj"; run >/dev/null
n_before="$(ls "$AG" | grep -c '^T2-feature-zeta-')"
mv "$P/mnt/track2" "$P/mnt/track2.off"
check "I16a run with the track-2 mount absent exit 0" 0 "$(run)"
check "I16b declared-but-unresolvable T2 files NOT pruned" "$n_before" "$(ls "$AG" | grep -c '^T2-feature-zeta-')"
mv "$P/mnt/track2.off" "$P/mnt/track2"
rc=$(MT_HOST=otherhost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" >"$W/out" 2>"$W/err"; echo $?)
check "I16c host-mismatch (no config) run exit 0" 0 "$rc"
check "I16d config not loadable: nothing pruned" "$n_before" "$(ls "$AG" | grep -c '^T2-feature-zeta-')"
bash "$GEN" --track 9 --branch gone --out-dir "$AG" --models sonnet,opus --efforts low >/dev/null
P="$W/proj"; check "I16e golden-TRUE: a track removed from the config IS pruned" 0 "$(run >/dev/null; [ -e "$AG/T9-gone-sonnet-low.md" ] && echo 1 || echo 0)"

# I10 lint -------------------------------------------------------------------------------------
bash -n "$INST" 2>/dev/null && ok "I10a bash -n clean" || bad "I10a bash -n clean"
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash "$INST" >"$W/sc" 2>&1 && ok "I10b shellcheck clean" || bad "I10b shellcheck clean" "$(head -3 "$W/sc")"; else ok "I10b shellcheck unavailable (SKIP-with-reason)"; fi
bash -n "$CONST/scripts/post_update_hook.sh" 2>/dev/null && ok "I10c post_update_hook.sh bash -n clean" || bad "I10c post_update_hook.sh bash -n clean"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
