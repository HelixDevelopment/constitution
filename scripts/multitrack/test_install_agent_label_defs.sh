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
    case "$e" in /Users) continue ;; esac   # /Users does not exist on Linux (I17i probes it explicitly); /tmp itself IS refused (R4-2)
    r="$(runh "$SH" --project-root "$P" --out-dir "$e")"
    [ "$r" = 6 ] || { bad_n=$((bad_n+1)); echo "    not refused: $e (exit $r)" >&2; }
  done <"$PPL"
  check "I17e every absolute protected_paths.list entry (except /Users, probed in I17i) is refused as out-dir" 0 "$bad_n"
else bad "I17e protected_paths.list readable"; fi
# R4-2/R4-3/R4-4: the strict-vs-exact class and under()'s slash handling (mutants MA, MB, ME)
STRICT_T="/bin /boot /dev /etc /lib /lib32 /lib64 /libx32 /opt /proc /root /run /sbin /srv /sys /usr"
EXACT_T="/var /home /mnt /media /snap /tmp /Users"
strict_i="$(sed -n 's/^SYS_STRICT=(\(.*\))$/\1/p' "$INST")"; exact_i="$(sed -n 's/^SYS_EXACT=(\(.*\))$/\1/p' "$INST")"
check "I17f the installer's SYS_STRICT list is the documented strict list" "$STRICT_T" "$strict_i"
check "I17g the installer's SYS_EXACT list is the documented exact-only list" "$EXACT_T" "$exact_i"
for sd in $STRICT_T; do
  check "I17h --out-dir '$sd/agentlabel-probe' (child of a strict dir) refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$sd/agentlabel-probe")"
done
for sd in $EXACT_T; do
  check "I17i --out-dir '$sd' (exact-only dir itself) refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$sd")"
  check "I17j golden-FALSE: --out-dir '$sd/agentlabel-probe/agents' (below an exact-only dir) not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir "$sd/agentlabel-probe/agents")"
done
check "I17k golden-FALSE: --out-dir ~/.claudeless/agents (prefix sibling of ~/.claude) not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claudeless/agents")"
check "I17l golden-FALSE: --out-dir /usrx/agents (prefix sibling of /usr) not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir /usrx/agents)"
check "I17m golden-FALSE: --out-dir /optimum/p (prefix sibling of /opt) not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir /optimum/p)"
# R4-1: the refusal must not depend on GNU 'realpath -m'. A realpath that fails (BSD/macOS without
# -m, busybox) is put first on PATH; '.', '..' and '//' must still be resolved, and the user's
# ~/.claude/agents must stay untouched on a NON-dry run.
RPS="$W/stub_realpath"; mkdir -p "$RPS"; printf '#!/bin/sh\nexit 1\n' >"$RPS/realpath"; chmod +x "$RPS/realpath"
runrp() { # fakehome args... (dry-run, failing realpath first on PATH)
  local fh="$1"; shift
  env -u CLAUDE_CONFIG_DIR PATH="$RPS:$PATH" HOME="$fh" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run "$@" >"$W/out" 2>"$W/err"; echo $?
}
mkdir -p "$SH/x"
for od in "$SH/x/../.claude/agents" /.. "$SH/x/.." "$SH/./x/.." "$SH//x/../" / // /. /./ /../.. "$SH/x/../.claude-x/agents" /etc/../etc /usr/./lib /tmp/.. /tmp/x/../ "$SH/plain/../../$(basename "$SH")/.claude/agents"; do
  check "I19a (R4-1) failing realpath: --out-dir '$od' refused (exit 6)" 6 "$(runrp "$SH" --project-root "$P" --out-dir "$od")"
done
check "I19b (R4-1) failing realpath: --project-root '\$HOME/x/..' refused (exit 6)" 6 "$(runrp "$SH" --project-root "$SH/x/..")"
check "I19c (R4-1) failing realpath: relative --out-dir '../.claude/agents' from ~/x refused" 6 "$(cd "$SH/x" && runrp "$SH" --project-root "$P" --out-dir ../.claude/agents)"
check "I19d (R4-1) golden-FALSE failing realpath: ordinary --out-dir with '.' and '..' not refused" 0 "$(runrp "$SH" --project-root "$P" --out-dir "$W/ordinary/./a/../agents")"
rm -f "$SH/dotreal/agents/T"*; : >"$SH/dotreal/agents/mine.md"; hm_before="$(ls "$SH/dotreal/agents")"
rc=$(env -u CLAUDE_CONFIG_DIR PATH="$RPS:$PATH" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir "$SH/x/../.claude/agents" >"$W/out" 2>"$W/err"; echo $?)
check "I19e (R4-1) failing realpath, NON-dry run into ~/x/../.claude/agents refused (exit 6)" 6 "$rc"
check "I19f (R4-1) the user's ~/.claude/agents is unchanged (nothing written, nothing pruned)" "$hm_before" "$(ls "$SH/dotreal/agents")"
# fail closed when a symlink cannot be read (no usable readlink): exit 6, never a guess
RLS="$W/stub_readlink"; mkdir -p "$RLS"; printf '#!/bin/sh\nexit 1\n' >"$RLS/readlink"; chmod +x "$RLS/readlink"; cp "$RPS/realpath" "$RLS/"
rc=$(env -u CLAUDE_CONFIG_DIR PATH="$RLS:$PATH" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run --project-root "$P" >"$W/out" 2>"$W/err"; echo $?)
check "I19g (R4-1) unreadable symlink (readlink fails, ~/.claude is a link) refused (exit 6)" 6 "$rc"
grep -q 'cannot canonicalise' "$W/err" && ok "I19h (R4-1) refusal names the canonicalisation failure" || bad "I19h (R4-1) refusal names the canonicalisation failure" "$(head -2 "$W/err")"
PH="$W/plainhome"; mkdir -p "$PH"
check "I19i (R4-1) golden-FALSE: readlink and realpath both failing, no symlink on any path -> not refused" 0 "$(env -u CLAUDE_CONFIG_DIR PATH="$RLS:$PATH" HOME="$PH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run --project-root "$P" >"$W/out" 2>"$W/err"; echo $?)"
# R5-1 (review round 5): per-process magic links (/proc/self, /proc/<pid>/cwd, /dev/fd, /dev/stdin) must
# not be resolved in a child process and then escaped with '..'. Any walk through a symlink under /proc
# is refused (exit 6), and the existing prefix is cross-checked with the kernel (cd -P) in a subshell.
mkdir -p "$SH/a/b"; SHB="$(basename "$SH")"
rm -f "$SH/dotreal/agents/T"*; : >"$SH/dotreal/agents/mine.md"; hm_before="$(ls "$SH/dotreal/agents")"
if [ -L /proc/self ]; then
  for sp in "" "$RPS"; do
    rc=$(cd "$SH/a/b" && env -u CLAUDE_CONFIG_DIR PATH="${sp:+$sp:}$PATH" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir "/proc/self/cwd/../../../$SHB/.claude/agents" >"$W/out" 2>"$W/err"; echo $?)
    check "I21a (R5-1) NON-dry --out-dir /proc/self/cwd/../../../<home>/.claude/agents from ~/a/b refused (exit 6)${sp:+, failing realpath}" 6 "$rc"
    check "I21b (R5-1) the user's ~/.claude/agents is unchanged${sp:+ (failing realpath)}" "$hm_before" "$(ls "$SH/dotreal/agents")"
    rm -f "$SH/dotreal/agents/T"*
  done
  for od in "/proc/thread-self/cwd/../../../$SHB/.claude/agents" "/proc/$$/cwd/../x" "/dev/fd/../../agents" "/dev/stdin/../../agents" "/proc/self/root$W/ordinary/agents"; do
    check "I21c (R5-1) --out-dir through a per-process magic link '$od' refused (exit 6)" 6 "$(cd "$SH/a/b" && runh "$SH" --project-root "$P" --out-dir "$od")"
  done
  grep -q 'magic link\|per-process' "$W/err" && ok "I21d (R5-1) refusal names the per-process link" || bad "I21d (R5-1) refusal names the per-process link" "$(head -2 "$W/err")"
else ok "I21a-d /proc/self absent on this host (SKIP-with-reason: topology_unsupported)"; fi
mkdir -p "$W/ordinary/a"; ln -sfn "$W/ordinary/a" "$W/ordlink"
check "I21e golden-FALSE: an ordinary symlink followed by '..' (no /proc) is not refused" 0 "$(runh "$SH" --project-root "$P" --out-dir "$W/ordlink/../agents")"
# R5-2: a symlink is followed BEFORE the '..' after it (kernel order). deep -> ~/a/b, so ~/deep/../.. is ~,
# not the parent of ~ (reviewer mutant RV7 resolved '..' lexically and wrote into ~/.claude/agents).
ln -sfn "$SH/a/b" "$SH/deep"
for sp in "" "$RPS"; do
  rc=$(env -u CLAUDE_CONFIG_DIR PATH="${sp:+$sp:}$PATH" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir "$SH/deep/../../.claude/agents" >"$W/out" 2>"$W/err"; echo $?)
  check "I22a (R5-2) NON-dry --out-dir ~/deep/../../.claude/agents (deep -> ~/a/b) refused (exit 6)${sp:+, failing realpath}" 6 "$rc"
  check "I22b (R5-2) the user's ~/.claude/agents is unchanged${sp:+ (failing realpath)}" "$hm_before" "$(ls "$SH/dotreal/agents")"
  rm -f "$SH/dotreal/agents/T"*
done
# I23 unit: the functions themselves, extracted from the installer (each layer must hold on its own)
FN="$W/canon_fns.sh"
{ sed -n '/^canon() {/,/^}/p' "$INST"; sed -n '/^canon_kcheck() {/,/^}/p' "$INST"; sed -n '/^canon_to() {/,/^}/p' "$INST"; grep '^refuse6() {' "$INST"; } >"$FN"
SHP="$(cd -P -- "$SH" && pwd -P)"
check "I23a (R5-2) canon: symlink followed before the following '..'" "$SHP/dotreal/agents" "$(bash -c '. "$1"; canon "$2"' _ "$FN" "$SH/deep/../../.claude/agents")"
check "I23b (R5-2) canon: '..' after a chained relative link" "$SHP/a" "$(bash -c '. "$1"; canon "$2"' _ "$FN" "$SH/deep/..")"
if [ -L /proc/self ]; then
  for pp in /proc/self/cwd/.. /proc/self /proc/thread-self/cwd "/proc/$$/cwd" /dev/fd/0 /dev/stdin "/proc/self/root/tmp"; do
    out="$(cd "$SH/a/b" && bash -c '. "$1"; canon "$2"' _ "$FN" "$pp")"; r=$?
    check "I23c (R5-1) canon refuses '$pp' (rc 2 = per-process link, no output)" "2:" "$r:$out"
  done
fi
check "I23d (R5-1) canon_kcheck: a lexical (wrong) canonicaliser is caught by the kernel cross-check (exit 6)" 6 "$(bash -c '. "$1"; canon() { printf "%s\n" "$1"; }; canon_to v "$2"' _ "$FN" "$SH/deep/../../.claude/agents" >/dev/null 2>&1; echo $?)"
check "I23e golden-FALSE: canon_to with the real canon accepts the same path" "$SHP/dotreal/agents:0" "$(bash -c '. "$1"; canon_to v "$2" && printf "%s" "$v"' _ "$FN" "$SH/deep/../../.claude/agents" 2>/dev/null; printf ':%s' "$?" )"
check "I23f (R4-1/R19) canon_to refuses when canon fails on the full path, even if the kernel cross-check alone would agree" 6 "$(bash -c '. "$1"; canon() { [ "$1" = "$2" ] && return 1; printf "%s\n" "$1"; }; T="$2"; canon() { [ "$1" = "$T" ] && return 1; printf "%s\n" "$1"; }; canon_to v "$T"' _ "$FN" "$SHP/nonexist/x" >/dev/null 2>&1; echo $?)"
check "I23g (R5-1) canon_to names a per-process link when canon returns 2" 1 "$(bash -c '. "$1"; canon() { return 2; }; canon_to v /x' _ "$FN" 2>&1 >/dev/null | grep -c 'per-process magic link')"
# ---- review round 6 (R6-1..R6-3): the class "a path string whose meaning depends on process state" --------------
# cwd, OLDPWD, CDPATH, PWD, option-like names (-, --), tildes, newline/glob/space, trailing slashes and //, very
# long paths, and ENAMETOOLONG / ELOOP / EACCES / ENOENT / ENOTDIR at a component. Every case either has one
# fixed meaning or is refused (exit 6); nothing depends on OLDPWD or CDPATH.
rm -f "$SH/dotreal/agents/T"*; : >"$SH/dotreal/agents/mine.md"; hm_before="$(ls "$SH/dotreal/agents")"
ienv() { env -u CLAUDE_CONFIG_DIR -u CDPATH HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" "$@"; }
oldpwd_env() { case "$1" in unset) printf '%s\n' -u OLDPWD ;; bogus) printf '%s\n' OLDPWD=/nonexistent/zz6 ;; *) printf '%s\n' "OLDPWD=$1" ;; esac; }
mkdir -p "$SH/a/b"
SEG="$(printf 'q%.0s' $(seq 1 200))"; DEEP="$W/deep6"; mkdir -p "$DEEP"
( cd -- "$DEEP" || exit 1; for _i in $(seq 1 25); do mkdir -- "$SEG" && cd -- "./$SEG" || exit 1; done; ln -s "$SH/a/b" ./-; ln -s "$SH/a/b" ./lk )
indeep() { ( cd -- "$DEEP" || exit 99; for _i in $(seq 1 25); do cd -- "./$SEG" || exit 99; done; "$@" ) }
# R6-1: cwd deeper than PATH_MAX + a symlink literally named '-' + a nonexistent component, OLDPWD unset/invalid/valid
for mode in unset bogus "$W"; do
  mapfile -t oe < <(oldpwd_env "$mode")
  rc=$(indeep env -u CLAUDE_CONFIG_DIR -u CDPATH "${oe[@]}" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir "-/nx6/../../../.claude/agents" >"$W/out" 2>"$W/err"; echo $?)
  check "I25a (R6-1) deep cwd, '-' symlink, OLDPWD=${mode##*/}: NON-dry -/nx6/../../../.claude/agents refused (exit 6)" 6 "$rc"
  check "I25b (R6-1) OLDPWD=${mode##*/}: the user's ~/.claude/agents is unchanged" "$hm_before" "$(ls "$SH/dotreal/agents")"
  rm -f "$SH/dotreal/agents/T"*
done
rc=$(indeep ienv bash "$INST" --project-root "$P" --out-dir "lk/../../.claude/newagents6" >"$W/out" 2>"$W/err"; echo $?)
check "I25c (R6-3 shape) deep cwd: NON-dry lk/../../.claude/newagents6 refused (exit 6), nothing created" "6:0" "$rc:$(find "$SH/dotreal" -maxdepth 1 -name newagents6 | wc -l)"
rc=$(indeep ienv bash "$INST" --project-root "$P" --out-dir "$W/abs6/agents" >"$W/out" 2>"$W/err"; echo $?)
check "I25d golden-FALSE: deep cwd with a short ABSOLUTE out-dir is accepted and written (exit 0, 10 T1 files)" "0:10" "$rc:$(find "$W/abs6/agents" -name 'T1-main-*' 2>/dev/null | wc -l)"
# R6-2: a relative '-' / '-/agents' / '--' out-dir means the directory of that name, whatever OLDPWD says
mkdir -p "$P/-" "$P/--"
for mode in unset bogus "$W"; do
  mapfile -t oe < <(oldpwd_env "$mode")
  for od in - -/agents -- ./-/agents; do
    rc=$(cd -- "$P" && env -u CLAUDE_CONFIG_DIR -u CDPATH "${oe[@]}" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir "$od" --dry-run >"$W/out" 2>"$W/err"; echo $?)
    check "I25e (R6-2) OLDPWD=${mode##*/}: relative --out-dir '$od' (a real project dir) accepted (exit 0)" 0 "$rc"
  done
done
rc=$(cd -- "$P" && env -u CLAUDE_CONFIG_DIR -u CDPATH OLDPWD="$SH/.claude" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$P" --out-dir -/agents >"$W/out" 2>"$W/err"; echo $?)
check "I25f (R6-2) NON-dry relative -/agents with OLDPWD=~/.claude writes into the project's '-/agents' only" "0:10:$hm_before" "$rc:$(find "$P/-/agents" -name 'T1-main-*' 2>/dev/null | wc -l):$(ls "$SH/dotreal/agents")"
rc=$(cd -- "$P" && ienv bash "$INST" --project-root "$P" --out-dir -- >"$W/out" 2>"$W/err"; echo $?)
check "I25g NON-dry relative --out-dir '--' writes into the project's '--' (exit 0)" "0:10" "$rc:$(find "$P/--" -maxdepth 1 -name 'T1-main-*' | wc -l)"
rm -rf -- "${P:?}/-" "${P:?}/--"
# CDPATH must never redirect the installer's own directory or a relative project root
DECOY="$W/decoy6"; mkdir -p "$DECOY/scripts/multitrack" "$DECOY/mnt"
rc=$(cd -- "$CONST" && env -u CLAUDE_CONFIG_DIR CDPATH="$DECOY" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash scripts/multitrack/install_agent_label_defs.sh --project-root "$P" --dry-run >"$W/out" 2>"$W/err"; echo $?)
check "I25h CDPATH pointing at a decoy with scripts/multitrack: installer run by relative path still works (exit 0)" 0 "$rc"
rc=$(cd -- "$P" && env -u CLAUDE_CONFIG_DIR CDPATH="$DECOY" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root mnt >"$W/out" 2>"$W/err"; echo $?)
check "I25i CDPATH: a relative --project-root 'mnt' means \$PWD/mnt, not the decoy's mnt" "0:1:0" "$rc:$([ -n "$(ls -A "$P/mnt/.claude/agents" 2>/dev/null)" ] && echo 1 || echo 0):$(find "$DECOY/mnt" -mindepth 1 | wc -l)"
rm -rf -- "${P:?}/mnt/.claude"
# PWD in the environment is not trusted (pwd -P is physical)
rc=$(cd -- "$P" && env -u CLAUDE_CONFIG_DIR -u CDPATH PWD="$SH/.claude" HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --dry-run >"$W/out" 2>"$W/err"; echo $?)
check "I25k env PWD=~/.claude with cwd=project: default project root is the physical cwd (exit 0)" 0 "$rc"
# unit (R6-1/R6-3): each guard layer on its own
{ sed -n '/^canon() {/,/^}/p' "$INST"; sed -n '/^canon_kcheck() {/,/^}/p' "$INST"; sed -n '/^canon_to() {/,/^}/p' "$INST"; grep '^refuse6() {' "$INST"; } >"$FN"
check "I25l (R6-3) canon_kcheck over a PARTIAL prefix (tail absent): a lexical canon is caught (exit 6)" 6 "$(bash -c '. "$1"; canon() { printf "%s\n" "$1"; }; canon_to v "$2"' _ "$FN" "$SH/deep/../../.claude/nonexist6/x" >/dev/null 2>&1; echo $?)"
check "I25m (R6-3) relative partial prefix with a lexical canon is caught (exit 6)" 6 "$(cd -- "$SH" && bash -c '. "$1"; canon() { printf "%s\n" "$1"; }; canon_to v "$2"' _ "$FN" "deep/../../.claude/nonexist6/x" >/dev/null 2>&1; echo $?)"
check "I25n golden-FALSE: the real canon accepts the same partial-prefix path" "$SHP/dotreal/nonexist6/x:0" "$(bash -c '. "$1"; canon_to v "$2" && printf "%s" "$v"' _ "$FN" "$SH/deep/../../.claude/nonexist6/x" 2>/dev/null; printf ':%s' "$?")"
mkdir -p "$W/u6/-"
check "I25o (R6-2) canon_kcheck: a relative '-' prefix is the directory '-', not OLDPWD (exit 0)" 0 "$(cd -- "$W/u6" && OLDPWD="$SH" bash -c '. "$1"; canon_to v "$2"' _ "$FN" "-/nx/y" >/dev/null 2>&1; echo $?)"
LONGP="$SHP"; for _i in $(seq 1 25); do LONGP="$LONGP/$SEG"; done
check "I25p (R6-1) canon refuses a path of PATH_MAX or more (rc 1, no output)" "1:0" "$(bash -c '. "$1"; canon "$2"' _ "$FN" "$LONGP/x" >"$W/lp.out"; printf '%s:%s' "$?" "$(wc -c <"$W/lp.out")")"
check "I25p2 (R6-1) canon refuses a relative path that is PATH_MAX or more from a deep cwd (rc 1)" 1 "$(indeep bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "-/nx6/../../../x"; echo $?)"
check "I25q canon refuses a component longer than NAME_MAX (rc 1)" 1 "$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$SHP/$SEG$SEG/x"; echo $?)"
: >"$W/u6/afile"
check "I25r (ENOTDIR) canon refuses a path through a regular file (afile/../x, rc 1)" 1 "$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$W/u6/afile/../x"; echo $?)"
ln -sfn "$W/u6/loopb" "$W/u6/loopa"; ln -sfn "$W/u6/loopa" "$W/u6/loopb"
check "I25s (ELOOP) canon refuses a symlink loop (rc 1)" 1 "$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$W/u6/loopa/x"; echo $?)"
U6P="$(cd -P -- "$W/u6" && pwd -P)"
check "I25t (ENOENT) golden-FALSE: nonexistent components stay lexical" "$U6P/nx/z" "$(bash -c '. "$1"; canon "$2"' _ "$FN" "$W/u6/nx/y/../z")"
check "I25u newline in a path: canon refuses (rc 1)" 1 "$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$W/u6/a"$'\n'"b"; echo $?)"
check "I25v trailing slashes and // : ~//deep/// is ~/a/b" "$SHP/a/b" "$(bash -c '. "$1"; canon "$2"' _ "$FN" "$SH//deep///")"
mkdir -p "$W/u6/~" "$W/u6/~+" "$W/u6/~-" "$W/u6/~root" "$W/u6/g*[x]? s"
for tw in "~" "~+" "~-" "~root" "g*[x]? s"; do
  check "I25w '$tw' is a literal name relative to cwd (canon_to rc 0, OLDPWD=~)" "$U6P/$tw/q:0" "$(cd -- "$W/u6" && OLDPWD="$SH" bash -c '. "$1"; canon_to v "$2" && printf "%s" "$v"' _ "$FN" "$tw/q" 2>/dev/null; printf ':%s' "$?")"
done
if [ "$(id -u)" != 0 ]; then
  mkdir -p "$W/u6/nox"; chmod 000 "$W/u6/nox"
  check "I25x (EACCES) canon refuses a component it cannot lstat (dir without search permission, rc 1)" 1 "$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$W/u6/nox/x"; echo $?)"
  chmod 755 "$W/u6/nox"
else ok "I25x running as root: EACCES cannot be produced (SKIP-with-reason)"; fi
# R5-3: a project root that cannot be entered (not a system dir) stops with exit 2, nothing written
if [ "$(id -u)" != 0 ]; then
  NE="$W/noenter"; mkdir -p "$NE"; chmod 000 "$NE"
  rc=$(env -u CLAUDE_CONFIG_DIR HOME="$SH" MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" bash "$INST" --project-root "$NE" >"$W/out" 2>"$W/err"; echo $?)
  chmod 755 "$NE"
  check "I24a (R5-3) un-enterable (chmod 000) project root stops with exit 2" 2 "$rc"
  [ ! -e "$NE/.claude" ] && ok "I24b (R5-3) nothing written under the un-enterable root" || bad "I24b (R5-3) nothing written under the un-enterable root"
  grep -q 'cannot be entered' "$W/err" && ok "I24c (R5-3) the reason is reported" || bad "I24c (R5-3) the reason is reported" "$(head -2 "$W/err")"
else ok "I24a-c running as root: chmod 000 does not block (SKIP-with-reason)"; fi
# R3-2 mutant killers (X3..X7)
ln -s "$W/nonexistent-target" "$SH/.claude-dangling"
check "I18a (X3) out-dir inside a DANGLING ~/.claude-* symlink refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude-dangling/agents")"
check "I18b (X6) out-dir EQUAL to a user config dir (~/.claude-y) refused" 6 "$(runh "$SH" --project-root "$P" --out-dir "$SH/.claude-x")"
RHR="$W/realhome"; mkdir -p "$RHR/proj"; ln -s "$RHR" "$W/homelink"
check "I18c (X5) HOME is a symlink: project root = its real target refused" 6 "$(runh "$W/homelink" --project-root "$RHR")"
mkdir -p "$W/x5/real/home" "$W/x5/links"; ln -s "$W/x5/real/home" "$W/x5/links/homelink"; git -C "$W/x5/real" init -q -b main 2>/dev/null
check "I18c2 (X5) HOME is a symlink: project root = an ancestor of its real target refused" 6 "$(runh "$W/x5/links/homelink" --project-root "$W/x5/real")"
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
# R3-5: a branch_pattern track whose mount HEAD does not match the pattern is UNRESOLVED (files kept, no T2-<head> set)
P="$W/proj"; run >/dev/null; n_z="$(ls "$AG" | grep -c '^T2-feature-zeta-')"
git -C "$P/mnt/track2" checkout -q -b hotfix/x 2>/dev/null
check "I20a HEAD outside branch_pattern: run exit 0" 0 "$(run)"
grep -q "does not match branch_pattern" "$W/out" && ok "I20b mismatch reported" || bad "I20b mismatch reported" "$(grep T2 "$W/out" | head -2)"
check "I20c no T2-hotfix-x files generated" 0 "$(ls "$AG" | grep -c '^T2-hotfix-x-')"
check "I20d T2-feature-zeta files kept (not pruned)" "$n_z" "$(ls "$AG" | grep -c '^T2-feature-zeta-')"
git -C "$P/mnt/track2" checkout -q feature/zeta 2>/dev/null
check "I20e golden-FALSE: HEAD matching the pattern still generates" 0 "$(run >/dev/null; grep -q 'does not match' "$W/out" && echo 1 || echo 0)"
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
