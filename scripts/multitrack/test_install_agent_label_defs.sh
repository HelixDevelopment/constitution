#!/usr/bin/env bash
# =============================================================================
# test_install_agent_label_defs.sh — hermetic tests for
#   scripts/multitrack/install_agent_label_defs.sh and its wiring into
#   scripts/post_update_hook.sh (§11.4.164 seam), §11.4.182 / §11.4.231(F).
#
# Purpose : prove the installer derives (track, branch, alias) from the LIVE
#   labeler identity of the checkout it installs into (never from a multitrack
#   config, a mount or an enclosing repository), refuses and touches NOTHING when
#   any of the three is unknown, writes the default 4 types, prunes only genuine
#   generated files of a superseded identity (alias change / rebind), never a
#   hand-made or hand-edited file, keeps --dry-run side-effect free, keeps its
#   output out of `git status` via .git/info/exclude, honours the consumer
#   opt-out, and that the post-update hook regenerates on every pull and stays
#   bash-3.2-safe.
# Usage   : bash scripts/multitrack/test_install_agent_label_defs.sh
# Side-effects: temp dir under ${TMPDIR:-/tmp}, removed on exit. No network.
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.164, §11.4.201, §11.4.224(A).
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
mkrepo() { mkdir -p "$1"; git -C "$1" init -q -b "${2:-main}"; git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; }
# run <alias|-> args... -> exit code; '-' = CLAUDE_CONFIG_DIR unset
run() {
  local al="$1"; shift
  if [ "$al" = - ]; then
    (cd "$P" && env -u CLAUDE_CONFIG_DIR -u AGENT_TYPE_LABEL_DEFS bash "$INST" --project-root "$P" "$@" >"$W/out" 2>"$W/err"); echo $?
  else
    (cd "$P" && env -u AGENT_TYPE_LABEL_DEFS CLAUDE_CONFIG_DIR="$W/cfg/.claude-$al" bash "$INST" --project-root "$P" "$@" >"$W/out" 2>"$W/err"); echo $?
  fi
}
names() { (cd "$1" 2>/dev/null && ls | LC_ALL=C sort | tr '\n' ' '); }
DEF4="T1-main-claude4-opus-high.md T1-main-claude4-opus-xhigh.md T1-main-claude4-sonnet-high.md T1-main-claude4-sonnet-medium.md "
DEF5="${DEF4//claude4/claude5}"

echo "install_agent_label_defs.sh test suite"
P="$W/proj"; mkrepo "$P"; AG="$P/.claude/agents"

# I01 install from the live identity ------------------------------------------------
check "I01a install exit 0" 0 "$(run claude4)"
check "I01b exactly the 4 default alias-bearing types of the current checkout" "$DEF4" "$(names "$AG")"
if python3 -I "$CHK" "$AG"/*.md >"$W/chk" 2>&1; then ok "I01c all files pass the strict parser"; else bad "I01c strict parser" "$(head -2 "$W/chk")"; fi
grep -q '^color: blue$' "$AG/T1-main-claude4-opus-high.md" && ok "I01d T1 colour blue" || bad "I01d T1 colour blue"
grep -qi 'restart the session' "$W/out" && ok "I01e changed install tells the operator a session refresh is needed (AL-9)" || bad "I01e session-refresh note"
# I02 idempotent
h1=$(tree_hash "$AG"); check "I02a rerun exit 0" 0 "$(run claude4)"; check "I02b byte-identical" "$h1" "$(tree_hash "$AG")"
! grep -qi 'restart the session' "$W/out" && grep -q 'written=0' "$W/out" && ok "I02c rerun reports written=0 and no refresh note" || bad "I02c rerun reports written=0" "$(tail -2 "$W/out")"

# I03 a multitrack config is NOT an input (AL-1 / AL-5) -----------------------------------
mkdir -p "$P/config/multitrack"; printf 'tracks: [ {{{ broken\n' >"$P/config/multitrack/fixturehost.yaml"
bash "$GEN" --track 2 --branch feature/zeta --alias claude3 --out-dir "$W/other" >/dev/null; cp "$W/other"/*.md "$AG/"
h0=$(tree_hash "$AG")
check "I03a malformed config present + identity unknown -> exit 6" 6 "$(MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" run -)"
check "I03b ...and NOTHING pruned or written" "$h0" "$(tree_hash "$AG")"
grep -qi 'identity' "$W/out" "$W/err" && ok "I03c refusal is loud and names the identity" || bad "I03c refusal names the identity"
chmod 000 "$P/config/multitrack/fixturehost.yaml"
check "I03d unreadable config + identity unknown -> exit 6, nothing touched" "6 $h0" "$(MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" run -) $(tree_hash "$AG")"
chmod 644 "$P/config/multitrack/fixturehost.yaml"
check "I03e malformed config + known identity -> exit 0" 0 "$(MT_HOST=fixturehost MT_CONFIG_DIR="$P/config/multitrack" run claude4)"
check "I03f own 4 present; another alias's generated types KEPT (AL2-1: ownership by alias)" "T1-main-claude4-opus-high.md T1-main-claude4-opus-xhigh.md T1-main-claude4-sonnet-high.md T1-main-claude4-sonnet-medium.md T2-feature-zeta-claude3-opus-high.md T2-feature-zeta-claude3-opus-xhigh.md T2-feature-zeta-claude3-sonnet-high.md T2-feature-zeta-claude3-sonnet-medium.md " "$(names "$AG")"
rm -rf "$P/config"

# I04 nested repository: the enclosing repo's branch is never used (AL-5) -------------------
O="$W/outer"; mkrepo "$O" outerbranch; P="$O/inner"; mkrepo "$P"; AGN="$P/.claude/agents"
check "I04a nested project exit 0" 0 "$(run claude4)"
check "I04b only the project's own branch (no T1-outerbranch-*)" "$DEF4" "$(names "$AGN")"
P="$W/proj"

# I05 unknown track / alias refuse loudly, touch nothing (never guess) ------------------------
F="$W/feat"; mkrepo "$F" feature/x; P="$F"
# the labeler derives the track from a /mnt/track<N> path, and this suite may itself run
# under one, so the '?'-track case drives the REAL installer + generator with a stand-in
# labeler that reports what the real one prints outside /mnt/track<N>.
FK="$W/fakelab"; mkdir -p "$FK"; cp "$INST" "$GEN" "$HERE/agent_label_lib.sh" "$HERE/agent_label_colors.tsv" "$FK/"
printf '#!/usr/bin/env bash\necho "(T?/feature/x - claude4 - ? - ?)"\n' >"$FK/track_branch_label.sh"
(cd "$F" && bash "$FK/install_agent_label_defs.sh" --project-root "$F" >"$W/out" 2>&1); rc=$?
check "I05a track '?' from the labeler -> exit 6" 6 "$rc"
[ ! -e "$F/.claude" ] && ok "I05b nothing written for an unknown track" || bad "I05b nothing written for an unknown track"
check "I05c --identity supplies the triple explicitly" "0 T2-feature-x-claude3-opus-high.md T2-feature-x-claude3-opus-xhigh.md T2-feature-x-claude3-sonnet-high.md T2-feature-x-claude3-sonnet-medium.md " "$(run claude4 --identity '2:feature/x:claude3') $(names "$F/.claude/agents")"
check "I05d --identity with a '?' field -> exit 2" 2 "$(run claude4 --identity '2:feature/x:?')"
P="$W/proj"

# I06 hand-made agents untouched ---------------------------------------------------------------
printf -- '---\nname: myagent\ndescription: "mine"\n---\nhand\n' >"$AG/myagent.md"
rm "$AG/T1-main-claude4-sonnet-medium.md"
printf -- '---\nname: T1-main-claude4-sonnet-medium\ndescription: "hand made"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nHAND\n' >"$AG/T1-main-claude4-sonnet-medium.md"
hm1=$(sha256sum "$AG/T1-main-claude4-sonnet-medium.md" "$AG/myagent.md")
check "I06a hand-made colliding file -> exit 3" 3 "$(run claude4)"
check "I06b hand-made files byte-unchanged" "$hm1" "$(sha256sum "$AG/T1-main-claude4-sonnet-medium.md" "$AG/myagent.md")"
grep -q 'T1-main-claude4-sonnet-medium' "$W/err" && ok "I06c refusal names the colliding file" || bad "I06c refusal names the colliding file"
rm "$AG/T1-main-claude4-sonnet-medium.md"; check "I06d after removing the collision, install heals" 0 "$(run claude4)"

# I07 --check -------------------------------------------------------------------------------------
check "I07a --check clean -> 0" 0 "$(run claude4 --check)"
rm "$AG/T1-main-claude4-opus-high.md"; check "I07b --check missing -> 1" 1 "$(run claude4 --check)"
[ ! -f "$AG/T1-main-claude4-opus-high.md" ] && ok "I07c --check wrote nothing" || bad "I07c --check wrote nothing"
run claude4 >/dev/null
sed -i 's/^color: blue$/color: red/' "$AG/T1-main-claude4-opus-high.md"; check "I07d --check hand-edited generated -> 1" 1 "$(run claude4 --check)"
check "I07e install refuses hand-edited generated -> 4" 4 "$(run claude4)"
rm "$AG/T1-main-claude4-opus-high.md"; run claude4 >/dev/null; check "I07f healed -> --check 0" 0 "$(run claude4 --check)"

# I08 several aliases share one checkout (topology probe 2026-10-15: ONE T1 checkout, alias
#     sets claude1/claude4/claude5 side by side): another alias's generated types are NEVER
#     pruned; only v1 files and THIS alias's superseded generated files are (AL2-1).
bash "$GEN" --track 1 --branch main --alias claude5 --out-dir "$AG" --types opus-low >/dev/null      # superseded type of the NEW alias
bash "$GEN" --track 1 --branch feature/old --alias claude5 --out-dir "$AG" --types opus-high >/dev/null # same alias, superseded branch
printf -- '---\nname: T1-main-claude5-opus-max\ndescription: "hand made, generator-shaped name"\nmodel: opus\neffort: max\ncolor: red\n---\nhand\n' >"$AG/T1-main-claude5-opus-max.md"
bash "$GEN" --track 1 --branch main --alias claude5 --out-dir "$W/ed" --types sonnet-low >/dev/null; sed -i 's/^You are /You really are /' "$W/ed/T1-main-claude5-sonnet-low.md"; cp "$W/ed/T1-main-claude5-sonnet-low.md" "$AG/"
v1="$AG/T1-main-opus-low.md"; fm=$'---\nname: T1-main-opus-low\ndescription: "(T1/main - <alias> - opus - low) x"\nmodel: opus\neffort: low\ncolor: blue\n---'; body='old body'
hv=$( { printf '%s\n' "$fm"; printf '%s\n' "$body"; } | sha256sum | cut -d' ' -f1)
{ printf '%s\n' "$fm"; printf '<!-- generated-by: gen_agent_label_defs.sh v1 (x); content-sha256: %s; y -->\n' "$hv"; printf '%s\n' "$body"; } >"$v1"
for x in html pdf docx; do printf 'export\n' >"$AG/T1-main-opus-low.$x"; printf 'export\n' >"$AG/T1-main-claude4-opus-high.$x"; printf 'export\n' >"$AG/T1-main-claude5-opus-low.$x"; done
printf 'export\n' >"$AG/myagent.html"
snap=$(tree_hash "$AG")
check "I08a --dry-run as claude5 exit 0" 0 "$(run claude5 --dry-run)"
check "I08b --dry-run deletes and writes NOTHING (RM4)" "$snap" "$(tree_hash "$AG")"
grep -q 'PLAN.*prune' "$W/out" && ok "I08c --dry-run plans the prunes" || bad "I08c --dry-run plans the prunes"
check "I08d --check as claude5 -> 1" 1 "$(run claude5 --check)"
check "I08e --check deletes nothing" "$snap" "$(tree_hash "$AG")"
check "I08f --no-prune keeps the v1 file" 1 "$(run claude5 --no-prune >/dev/null; [ -e "$AG/T1-main-opus-low.md" ] && echo 1 || echo 0)"
EX="$(git -C "$P" rev-parse --path-format=absolute --git-path info/exclude)"
check "I08f2 a --no-prune leftover stays excluded from git status" 0 "$(git -C "$P" status --porcelain --untracked-files=all | grep -c 'T1-main-opus-low')"
check "I08g claude5 install exit 0" 0 "$(run claude5)"
for n in $DEF5; do [ -e "$AG/$n" ] || bad "I08h new alias type $n present"; done; ok "I08h the 4 claude5 types are present"
check "I08i claude4's 4 generated types KEPT (another alias, maybe a live session)" "$DEF4" "$(cd "$AG" && ls T1-main-claude4-*.md | LC_ALL=C sort | tr '\n' ' ')"
read -r -a D5A <<<"$DEF5"
lefto=""; for f in "$AG"/T1-main-claude5-*.md "$AG"/T1-feature-old-claude5-*.md "$AG"/T1-main-opus-low.md; do
  [ -e "$f" ] || continue; b="${f##*/}"; keep=1; for d in "${D5A[@]}"; do [ "$d" = "$b" ] && keep=0; done; [ "$keep" -eq 1 ] && lefto="$lefto$b "
done
check "I08j v1 + claude5's superseded type/branch pruned; hand-made and hand-edited kept" "T1-main-claude5-opus-max.md T1-main-claude5-sonnet-low.md " "$lefto"
grep -q 'WARN.*T1-main-claude5-sonnet-low' "$W/err" && ok "I08k hand-edited superseded file is WARNed, not pruned (RM3)" || bad "I08k hand-edited superseded WARN"
check "I08l siblings of pruned files deleted with them (AL2-2)" "0 0" "$(ls "$AG"/T1-main-opus-low.* 2>/dev/null | wc -l) $(ls "$AG"/T1-main-claude5-opus-low.* 2>/dev/null | wc -l)"
check "I08m siblings of kept / hand-made files untouched" "3 1" "$(ls "$AG"/T1-main-claude4-opus-high.{html,pdf,docx} 2>/dev/null | wc -l) $(ls "$AG"/myagent.html 2>/dev/null | wc -l)"
n5() { local c=0 d; for d in "${D5A[@]}"; do [ -e "$AG/$d" ] && c=$((c+1)); done; echo "$c"; }
check "I08n reinstall by claude4 keeps claude5's types" "0 4" "$(run claude4) $(n5)"
[ -e "$AG/myagent.md" ] && ok "I08o unrelated hand-made agent kept" || bad "I08o unrelated hand-made agent kept"

# I09 git status stays clean of generated files and their export siblings (AL-11, AL2-1, AL2-2) ------
st="$(git -C "$P" status --porcelain --untracked-files=all | sed 's/^?? //' | LC_ALL=C sort | tr '\n' ' ')"
check "I09a only hand-made files show (both aliases' generated types + siblings + kept hand-edited are excluded)" ".claude/agents/T1-main-claude5-opus-max.md .claude/agents/myagent.html .claude/agents/myagent.md " "$st"
check "I09b one exclude block for the directory" 1 "$(grep -c '^# >>> agent-label-defs' "$EX")"
grep -q 'T1-main-claude5-opus-xhigh.md' "$EX" && grep -q 'T1-main-claude4-opus-xhigh.md' "$EX" && ok "I09c exclude lists every alias's generated names" || bad "I09c exclude lists every alias's generated names"
grep -q 'T1-main-claude4-opus-high.html' "$EX" && ok "I09d exclude lists export siblings (RV2b)" || bad "I09d exclude lists export siblings"
rm -f "$AG/T1-main-claude5-opus-max.md" "$AG/T1-main-claude5-sonnet-low.md" "$AG/myagent.html" "$AG"/T1-main-claude4-opus-high.{html,pdf,docx}
P2="$W/noex"; mkrepo "$P2"; P="$P2"; run claude4 --no-git-exclude >/dev/null
check "I09e --no-git-exclude leaves the files visible" 4 "$(git -C "$P" status --porcelain --untracked-files=all | grep -c 'T1-main-claude4')"
P="$W/proj"

# I16 exclude-block identity (AL3-1 class): unique per worktree + directory, exact line matching -----
#   topology: linked worktrees share ONE info/exclude (the common git dir); separate clones do not.
Q="$W/wtmain"; mkrepo "$Q"; git -C "$Q" worktree add -q -b zz "$W/wtlinked" 2>/dev/null
P="$Q"; run claude4 >/dev/null
P="$W/wtlinked"; run claude4 --identity '2:zz:claude3' >/dev/null
check "I16a linked worktrees: main worktree stays clean after the linked one installs" 0 "$(git -C "$Q" status --porcelain --untracked-files=all | grep -c 'T1-main-claude4')"
check "I16b linked worktrees: linked worktree clean too" 0 "$(git -C "$W/wtlinked" status --porcelain --untracked-files=all | grep -c 'T2-zz-claude3')"
Q2="$W/sp"; mkrepo "$Q2"; P="$Q2"
run claude4 --out-dir "$Q2/a b" >/dev/null; run claude4 --out-dir "$Q2/a" >/dev/null
check "I16c out-dirs 'a' and 'a b' both stay clean (no prefix collision)" 0 "$(git -C "$Q2" status --porcelain --untracked-files=all | grep -c 'claude4')"
run claude4 --out-dir "$Q2/a" >/dev/null
check "I16c2 re-running 'a' with both blocks present keeps 'a b' excluded (exact begin match)" 0 "$(git -C "$Q2" status --porcelain --untracked-files=all | grep -c 'claude4')"
EXq="$(git -C "$Q2" rev-parse --path-format=absolute --git-path info/exclude)"; qab="$(cd "$Q2/a b" && pwd -P)"
check "I16c3 the 'a b' block keeps both its markers after 'a' re-runs (exact begin match)" "1 1" "$(grep -cxF "# >>> agent-label-defs v2 $qab" "$EXq") $(grep -cxF "# <<< agent-label-defs v2 $qab" "$EXq")"
run claude4 --out-dir "$Q2/x[1]" >/dev/null
check "I16d gitignore metacharacters in the out-dir are escaped" 0 "$(git -C "$Q2" status --porcelain --untracked-files=all | grep -c 'claude4')"
Q3="$W/legacy"; mkrepo "$Q3"; P="$Q3"; EX3="$(git -C "$Q3" rev-parse --path-format=absolute --git-path info/exclude)"
{ echo '# >>> agent-label-defs .claude/agents T1 (managed by install_agent_label_defs.sh; host-derived agent types, do not commit)'; echo '/.claude/agents/T1-main-old-opus-high.md'; echo '# <<< agent-label-defs .claude/agents T1'; echo 'my-private-ignore.log'; echo 'secrets.env'; } >>"$EX3"
run claude4 >/dev/null
check "I16e user lines after an old-format block survive (RV4)" "1 1" "$(grep -cx 'my-private-ignore.log' "$EX3") $(grep -cx 'secrets.env' "$EX3")"
check "I16f the old-format block is replaced" 0 "$(grep -c 'T1-main-old-opus-high' "$EX3")"
{ echo '# >>> agent-label-defs .claude/agents (managed by install_agent_label_defs.sh; host-derived agent types, do not commit)'; echo '/.claude/agents/unterminated.md'; echo 'keep-me.log'; } >>"$EX3"
run claude4 >/dev/null
check "I16g an UNTERMINATED old block never swallows the lines after it" 1 "$(grep -cx 'keep-me.log' "$EX3")"
P="$W/proj"
# RV5 / RV6: ownership is EXACT equality of sanitised aliases
Q4="$W/own"; mkrepo "$Q4"; P="$Q4"; A4="$Q4/.claude/agents"
bash "$GEN" --track 1 --branch main --alias Claude4 --out-dir "$A4" --types opus-low >/dev/null
run claude4 >/dev/null
check "I17a a case variant of the alias owns (and prunes) its superseded file (RV5)" 0 "$(ls "$A4"/T1-main-claude4-opus-low.md 2>/dev/null | wc -l)"
bash "$GEN" --track 1 --branch main --alias kimi --out-dir "$A4" >/dev/null
run claude4 --identity '1:main:kimi-for-coding' >/dev/null
check "I17b kimi-for-coding never prunes kimi's types (RV6)" 4 "$(find "$A4" -maxdepth 1 -name 'T1-main-kimi-*.md' ! -name 'T1-main-kimi-for-coding-*' | wc -l)"
run claude4 --identity '1:main:kimi' >/dev/null
check "I17c kimi never prunes kimi-for-coding's types (RV6)" 4 "$(ls "$A4"/T1-main-kimi-for-coding-*.md 2>/dev/null | wc -l)"
# --remove-alias: the documented way to retire an alias's types (AL3-3d)
printf -- '---\nname: T1-main-kimi-opus-max\ndescription: "hand made"\nmodel: opus\neffort: max\ncolor: red\n---\nhand\n' >"$A4/T1-main-kimi-opus-max.md"
for x in html pdf docx; do printf 'e\n' >"$A4/T1-main-kimi-opus-high.$x"; done
snap4=$(tree_hash "$A4")
check "I18a --remove-alias kimi --dry-run deletes nothing" "0 $snap4" "$(run claude4 --remove-alias kimi --dry-run) $(tree_hash "$A4")"
check "I18b --remove-alias kimi exit 0" 0 "$(run claude4 --remove-alias kimi)"
check "I18c only kimi's GENERATED files (+ siblings) removed; its hand-made file and other aliases kept" "1 0 4 4" "$(ls "$A4"/T1-main-kimi-opus-max.md | wc -l) $( (ls "$A4"/T1-main-kimi-opus-high.* "$A4"/T1-main-kimi-sonnet-*.md 2>/dev/null) | wc -l) $(ls "$A4"/T1-main-kimi-for-coding-*.md | wc -l) $(ls "$A4"/T1-main-claude4-*.md | wc -l)"
check "I18d the exclude block no longer lists kimi's removed files" 0 "$(grep -c 'T1-main-kimi-opus-high' "$(git -C "$Q4" rev-parse --path-format=absolute --git-path info/exclude)")"
check "I18e --remove-alias with '?' -> exit 2" 2 "$(run claude4 --remove-alias '?')"
P="$W/proj"

# I19 exclude-block parser: enumerated block states (structural round 5, AL4-1). Every case carries
#   a control needle line that must survive two runs; exactly one block of our key must remain;
#   another directory's complete block must survive; generated files stay out of git status.
mkdir -p "$W/otherdir/.claude/agents"; OD_OTHER="$(cd "$W/otherdir/.claude/agents" && pwd -P)"   # exists, so not collected as stale
OTHERB="# >>> agent-label-defs v2 $OD_OTHER"; OTHERE="# <<< agent-label-defs v2 $OD_OTHER"
exstate() { # name content-generator-function [out-dir-relative]
  local name="$1" gen="$2" rel="${3:-.claude/agents}" R EXF od ok=1 why=""
  R="$W/ex_$name"; mkrepo "$R"; mkdir -p "$R/$rel"; od="$(cd "$R/$rel" && pwd -P)"
  EXF="$(git -C "$R" rev-parse --path-format=absolute --git-path info/exclude)"
  "$gen" "$od" >>"$EXF"
  P="$R"; run claude4 --out-dir "$R/$rel" >/dev/null; run claude4 --out-dir "$R/$rel" >/dev/null
  [ "$(grep -c "^NEEDLE-$name" "$EXF")" -eq 1 ] || { ok=0; why="$why needle-lost"; }
  [ "$(grep -cxF "# >>> agent-label-defs v2 $od" "$EXF")" -eq 1 ] || { ok=0; why="$why our-begin=$(grep -cxF "# >>> agent-label-defs v2 $od" "$EXF")"; }
  [ "$(grep -cxF "# <<< agent-label-defs v2 $od" "$EXF")" -eq 1 ] || { ok=0; why="$why our-end=$(grep -cxF "# <<< agent-label-defs v2 $od" "$EXF")"; }
  if grep -q 'OTHERFILE' "$EXF.expect_other" 2>/dev/null || [ "${EXPECT_OTHER:-0}" = 1 ]; then
    [ "$(grep -cxF "$OTHERB" "$EXF")" -eq 1 ] && [ "$(grep -cxF '/.claude/agents/OTHERFILE.md' "$EXF")" -eq 1 ] || { ok=0; why="$why other-block-lost"; }
  fi
  [ "$(git -C "$R" status --porcelain --untracked-files=all | grep -c 'claude4')" -eq 0 ] || { ok=0; why="$why generated-visible"; }
  [ "$(grep -c '^# >>> agent-label-defs' "$EXF")" -eq $((1 + ${EXPECT_OTHER:-0})) ] || { ok=0; why="$why begin-markers=$(grep -c '^# >>> agent-label-defs' "$EXF")"; }
  [ "$(grep -c '^# <<< agent-label-defs' "$EXF")" -eq $((1 + ${EXPECT_OTHER:-0})) ] || { ok=0; why="$why end-markers=$(grep -c '^# <<< agent-label-defs' "$EXF")"; }
  if [ "${OLDGONE:-0}" = 1 ] && [ "$(grep -c 'T1-old-x' "$EXF")" -ne 0 ]; then ok=0; why="$why old-block-content-kept"; fi
  [ "$ok" -eq 1 ] && ok "I19 block state '$name' handled" || bad "I19 block state '$name'" "$why"
  P="$W/proj"
}
c_none()    { printf 'NEEDLE-none\n'; }
c_empty()   { printf '# >>> agent-label-defs v2 %s\n# <<< agent-label-defs v2 %s\nNEEDLE-empty\n' "$1" "$1"; }
c_full()    { printf '# >>> agent-label-defs v2 %s\n# managed\n/.claude/agents/T1-old-x-opus-high.md\n# <<< agent-label-defs v2 %s\nNEEDLE-full\n' "$1" "$1"; }
c_dup()     { c_full "$1" | sed 's/NEEDLE-full//'; c_full "$1" | sed 's/NEEDLE-full/NEEDLE-dup/'; }
c_unterm()  { printf '# >>> agent-label-defs v2 %s\n/.claude/agents/T1-old-x-opus-high.md\nNEEDLE-unterm\nsecrets.env\n%s\n/.claude/agents/OTHERFILE.md\n%s\n' "$1" "$OTHERB" "$OTHERE"; }
c_nested()  { printf '# >>> agent-label-defs v2 %s\n%s\n/.claude/agents/OTHERFILE.md\n%s\n# <<< agent-label-defs v2 %s\nNEEDLE-nested\n' "$1" "$OTHERB" "$OTHERE" "$1"; }
c_reorder() { printf '# <<< agent-label-defs v2 %s\nNEEDLE-reorder\n# >>> agent-label-defs v2 %s\n' "$1" "$1"; }
c_crlf()    { printf '# >>> agent-label-defs v2 %s\r\n/.claude/agents/T1-old-x-opus-high.md\r\n# <<< agent-label-defs v2 %s\r\nNEEDLE-crlf\r\n' "$1" "$1"; }
c_needle()  { printf 'NEEDLE-%s\n' "$CASE"; }
c_huge()    { local i; for i in $(seq 1 5000); do printf 'user-pattern-%d\n' "$i"; done; printf 'NEEDLE-huge\n'; }
exstate none c_none; exstate empty c_empty
OLDGONE=1 EXPECT_OTHER=0 exstate full c_full; OLDGONE=1 EXPECT_OTHER=0 exstate dup c_dup
EXPECT_OTHER=1 exstate unterm c_unterm; EXPECT_OTHER=1 exstate nested c_nested
EXPECT_OTHER=0 exstate reorder c_reorder; OLDGONE=1 EXPECT_OTHER=0 exstate crlf c_crlf
CASE=backslash EXPECT_OTHER=0 exstate backslash c_needle 'back\tslash\\n'   # backslash-t: an escape awk -v would interpret
CASE=glob EXPECT_OTHER=0 exstate glob c_needle 'g[1]*?'
EXPECT_OTHER=0 exstate huge c_huge
check "I19b unterminated old block: the lines after it survive (AL4-1a)" 1 "$(grep -cx 'secrets.env' "$(git -C "$W/ex_unterm" rev-parse --path-format=absolute --git-path info/exclude)")"
# RV13: a newline in the out-dir writes no exclude line at all
Rn="$W/ex_nl"; mkrepo "$Rn"; mkdir -p "$Rn/a"$'\n'"line"; EXn="$(git -C "$Rn" rev-parse --path-format=absolute --git-path info/exclude)"; hn="$(sha256sum <"$EXn")"
P="$Rn"; run claude4 --out-dir "$Rn/a"$'\n'"line" >/dev/null
check "I19c newline in the out-dir: exclude file unchanged (RV13)" "$hn" "$(sha256sum <"$EXn")"
P="$W/proj"
# I20 concurrent installs in linked worktrees (shared info/exclude) never lose a block (AL4-1c)
Cm="$W/cc"; mkrepo "$Cm"; git -C "$Cm" worktree add -q -b ccz "$W/ccl" 2>/dev/null
EXc="$(git -C "$Cm" rev-parse --path-format=absolute --git-path info/exclude)"; nloss=0
for it in $(seq 1 100); do
  : >"$EXc"
  (cd "$Cm" && CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" bash "$INST" --project-root "$Cm" >/dev/null 2>&1) &
  (cd "$W/ccl" && bash "$INST" --project-root "$W/ccl" --identity "2:ccz:claude$((it % 3 + 1))" >/dev/null 2>&1) &
  wait
  n1=$(git -C "$Cm" status --porcelain --untracked-files=all | grep -c 'T1-main-claude4' || true)
  n2=$(git -C "$W/ccl" status --porcelain --untracked-files=all | grep -c "T2-ccz-claude$((it % 3 + 1))" || true)
  [ "$n1" -eq 0 ] && [ "$n2" -eq 0 ] || nloss=$((nloss+1))
done
check "I20 100 concurrent install pairs in linked worktrees lose no exclude block (AL4-1c)" 0 "$nloss"
# I20b the same with the read->rename window widened (deterministic: an unlocked writer always loses)
#   and I20c a holder killed with SIGKILL while holding the lock never wedges it (kernel flock)
cc_pair() { # extra-env... : one concurrent pair, prints 1 when a block was lost
  : >"$EXc"
  (cd "$Cm" && env "$@" CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" bash "$INST" --project-root "$Cm" >/dev/null 2>&1) &
  (cd "$W/ccl" && env "$@" bash "$INST" --project-root "$W/ccl" --identity "2:ccz:claude2" >/dev/null 2>&1) &
  wait
  if [ "$(git -C "$Cm" status --porcelain --untracked-files=all | grep -c 'T1-main-claude4' || true)" -eq 0 ] &&
     [ "$(git -C "$W/ccl" status --porcelain --untracked-files=all | grep -c 'T2-ccz-claude2' || true)" -eq 0 ]; then echo 0; else echo 1; fi
}
nl2=0; for it in 1 2 3; do nl2=$((nl2 + $(cc_pair AGENT_LABEL_EXCL_DELAY=0.4))); done
check "I20b 3 widened-window concurrent pairs lose no block (flock)" 0 "$nl2"
LKc="$(dirname "$EXc")/.agent-label-defs.lock"
hold_lock() { ( exec 9>>"$LKc"; flock -x 9; exec sleep 300 ) & hpid=$!; sleep 0.5; }   # one process holds the fd
hold_lock; kill -9 "$hpid" 2>/dev/null; wait "$hpid" 2>/dev/null
: >"$EXc"; t0=$(date +%s)
P="$Cm"; run claude4 >/dev/null; P="$W/proj"; t1=$(date +%s)
check "I20c holder killed while holding the lock: next install writes its block at once" "1 0" "$(grep -c '^# >>> agent-label-defs v2 ' "$EXc") $(( (t1 - t0) > 15 ? 1 : 0 ))"
# I20d a LIVE holder: after the (shortened) wait the install warns and writes no block
hold_lock; : >"$EXc"
(cd "$Cm" && AGENT_LABEL_LOCK_WAIT=1 CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" bash "$INST" --project-root "$Cm" >"$W/out" 2>"$W/err")
kill -9 "$hpid" 2>/dev/null; wait "$hpid" 2>/dev/null
check "I20d live holder: WARN, exclude file untouched" "1 0" "$(grep -c 'could not lock' "$W/err") $(wc -c <"$EXc")"
# I20e a killed holder's temp file is removed by the next install (it holds the lock)
echo junk >"$EXc.tmp.999999"; P="$Cm"; run claude4 >/dev/null; P="$W/proj"
check "I20e stale exclude temp file removed under the lock" 0 "$(ls "$EXc".tmp.* 2>/dev/null | wc -l)"
# I20f flock missing -> distinct exit 8, nothing written or pruned, exclude untouched (AL5-1)
Fm="$W/nofl"; mkrepo "$Fm"; EXf="$(git -C "$Fm" rev-parse --path-format=absolute --git-path info/exclude)"; hf="$(sha256sum <"$EXf")"
P="$Fm"
check "I20f flock missing: exit 8, no agents dir, exclude byte-identical" "8 0 $hf" "$(AGENT_LABEL_FLOCK_BIN=/nonexistent/flock run claude4) $(ls -d "$Fm/.claude/agents" 2>/dev/null | wc -l) $(sha256sum <"$EXf")"
check "I20g flock missing + --remove-alias: exit 8" 8 "$(AGENT_LABEL_FLOCK_BIN=/nonexistent/flock run claude4 --remove-alias kimi)"
check "I20h flock missing + --no-git-exclude: installs (no lock needed), exclude untouched" "0 4 $hf" "$(AGENT_LABEL_FLOCK_BIN=/nonexistent/flock run claude4 --no-git-exclude) $(ls "$Fm/.claude/agents" | wc -l) $(sha256sum <"$EXf")"
check "I20i flock missing + --check / --dry-run: no lock needed" "0 0" "$(AGENT_LABEL_FLOCK_BIN=/nonexistent/flock run claude4 --check) $(AGENT_LABEL_FLOCK_BIN=/nonexistent/flock run claude4 --dry-run)"
P="$W/proj"
# I22 a removed linked worktree's block is collected; a live one's is kept
Gm="$W/gc"; mkrepo "$Gm"; git -C "$Gm" worktree add -q -b gcz "$W/gcl" 2>/dev/null; git -C "$Gm" worktree add -q -b gcy "$W/gcl2" 2>/dev/null
(cd "$W/gcl" && bash "$INST" --project-root "$W/gcl" --identity "2:gcz:claude1" >/dev/null 2>&1)
(cd "$W/gcl2" && bash "$INST" --project-root "$W/gcl2" --identity "3:gcy:claude1" >/dev/null 2>&1)
EXg="$(git -C "$Gm" rev-parse --path-format=absolute --git-path info/exclude)"
gl="$(cd "$W/gcl" && pwd -P)"; gl2="$(cd "$W/gcl2" && pwd -P)"
git -C "$Gm" worktree remove --force "$W/gcl"
mv "$W/gcl2" "$W/gcl2.away"   # unmounted: gone from disk but still listed by git (R1b)
P="$Gm"; run claude4 >/dev/null; P="$W/proj"
check "I22 removed worktree's block fully collected: begin, end and entries (R17)" "0 0 0" "$(grep -cxF "# >>> agent-label-defs v2 $gl/.claude/agents" "$EXg") $(grep -cxF "# <<< agent-label-defs v2 $gl/.claude/agents" "$EXg") $(grep -c 'T2-gcz-' "$EXg")"
check "I22b unmounted but still-listed worktree's block kept (R1b)" "1 1" "$(grep -cxF "# >>> agent-label-defs v2 $gl2/.claude/agents" "$EXg") $(grep -cxF "# <<< agent-label-defs v2 $gl2/.claude/agents" "$EXg")"
mv "$W/gcl2.away" "$W/gcl2"
check "I22c after remount its generated files are still invisible to git" 0 "$(git -C "$W/gcl2" status --porcelain --untracked-files=all | grep -c 'T3-gcy-')"
# I21 --remove-alias mode x flag matrix (AL4-2) and hand-edited files (RV15)
Rr="$W/rm"; mkrepo "$Rr"; Ar="$Rr/.claude/agents"; P="$Rr"
bash "$GEN" --track 1 --branch main --alias kimi --out-dir "$Ar" >/dev/null
bash "$GEN" --track 1 --branch main --alias kimi --out-dir "$W/rmed" --types sonnet-low >/dev/null; sed -i 's/^You are /You really are /' "$W/rmed/T1-main-kimi-sonnet-low.md"; cp "$W/rmed/T1-main-kimi-sonnet-low.md" "$Ar/"
hr=$(tree_hash "$Ar")
for fl in --check --no-prune "--identity 1:main:x" "--types opus-low" --all-types; do
  hr=$(tree_hash "$Ar")
  # shellcheck disable=SC2086 # word-splitting the flag and its value on purpose
  check "I21 --remove-alias refuses '$fl' (exit 2, nothing touched)" "2 $hr" "$(run claude4 --remove-alias kimi $fl) $(tree_hash "$Ar")"
done
EXr="$(git -C "$Rr" rev-parse --path-format=absolute --git-path info/exclude)"; hx="$(sha256sum <"$EXr")"
check "I21b --remove-alias --dry-run touches neither the agents dir nor the exclude file (R6)" "0 $hr $hx" "$(run claude4 --remove-alias kimi --dry-run) $(tree_hash "$Ar") $(sha256sum <"$EXr")"
run claude4 --remove-alias kimi >/dev/null
check "I21c --remove-alias keeps the alias's hand-edited file (RV15)" 1 "$(ls "$Ar"/T1-main-kimi-sonnet-low.md 2>/dev/null | wc -l)"
P="$W/proj"

# I10 opt-out --------------------------------------------------------------------------------------
P3="$W/opt"; mkrepo "$P3"; P="$P3"
check "I10a AGENT_TYPE_LABEL_DEFS=off -> exit 0" 0 "$( (cd "$P" && CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" AGENT_TYPE_LABEL_DEFS=off bash "$INST" --project-root "$P" >"$W/out" 2>&1); echo $?)"
[ ! -e "$P/.claude/agents" ] && ok "I10b opt-out writes nothing" || bad "I10b opt-out writes nothing"
mkdir -p "$P/.claude/agents"; touch "$P/.claude/agents/.agent-label-defs-disabled"
bash "$GEN" --track 1 --branch main --alias claude9 --out-dir "$P/.claude/agents" >/dev/null; hh=$(tree_hash "$P/.claude/agents")
check "I10c marker-file opt-out -> exit 0, nothing written or pruned" "0 $hh" "$(run claude4) $(tree_hash "$P/.claude/agents")"
P="$W/proj"

# I11 passthrough + usage ----------------------------------------------------------------------------
rm -rf "$W/o"; check "I11a --out-dir + --types" "0 T1-main-claude4-opus-max.md " "$(run claude4 --out-dir "$W/o" --types opus-max) $(names "$W/o")"
check "I11b --all-types -> 10" 10 "$(run claude4 --out-dir "$W/o10" --all-types >/dev/null; ls "$W/o10" | wc -l)"
check "I11c usage: unknown flag -> 2" 2 "$(run claude4 --bogus)"
check "I11d bash < 4 -> exit 7 (simulated)" 7 "$(AGENT_LABEL_BASH_MAJOR=3 run claude4)"

# I12 hook wiring (hermetic fixture constitution) -----------------------------------------------------
FC="$W/fakeconst"; mkdir -p "$FC/scripts/multitrack" "$FC/scripts/gates" "$FC/scripts/hooks"
printf 'stub\n' >"$FC/Constitution.md"
cp "$CONST/scripts/post_update_hook.sh" "$FC/scripts/"
cp "$HERE/multitrack_config.sh" "$HERE/track_branch_label.sh" "$HERE/agent_label_lib.sh" "$GEN" "$INST" "$HERE/agent_label_colors.tsv" "$CHK" "$FC/scripts/multitrack/"
git -C "$FC" init -q -b main; git -C "$FC" add -A; git -C "$FC" -c user.email=t@t -c user.name=t commit -q -m c
HP="$W/hp"; mkrepo "$HP"
hookrun() { (cd "$HP" && env -u AGENT_TYPE_LABEL_DEFS CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"; echo $?); }
check "I12a hook exit 0 on a no-change pull" 0 "$(hookrun)"
check "I12b hook generated the 4 default definitions" "$DEF4" "$(names "$HP/.claude/agents")"
hh=$(tree_hash "$HP/.claude/agents"); hookrun >/dev/null; check "I12c hook rerun idempotent" "$hh" "$(tree_hash "$HP/.claude/agents")"
printf -- '---\nname: T1-main-claude4-opus-high\ndescription: "hand"\n---\nH\n' >"$W/hand.md"; cp "$W/hand.md" "$HP/.claude/agents/T1-main-claude4-opus-high.md"
check "I12d hook is NON-fatal when a hand-made file collides" 0 "$(hookrun)"
cmp -s "$W/hand.md" "$HP/.claude/agents/T1-main-claude4-opus-high.md" && ok "I12e hook left the hand-made file alone" || bad "I12e hook left the hand-made file alone"
grep -qi 'hand-made' "$W/hout" "$W/herr" && ok "I12f hook reports the collision as a warning" || bad "I12f hook reports the collision"
rm "$HP/.claude/agents/T1-main-claude4-opus-high.md"
hrc=$( (cd "$HP" && env -u CLAUDE_CONFIG_DIR CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"); echo $?)
check "I12g hook non-fatal when the identity is unknown" 0 "$hrc"
grep -qi 'identity' "$W/hout" "$W/herr" && ok "I12h unknown identity reported by the hook, not silent" || bad "I12h unknown identity reported"
rm "$FC/scripts/multitrack/install_agent_label_defs.sh"; check "I12i hook non-fatal when installer is missing" 0 "$(hookrun)"
grep -qi 'install_agent_label_defs' "$W/hout" "$W/herr" && ok "I12j missing installer reported, not silent" || bad "I12j missing installer reported"
cp "$INST" "$FC/scripts/multitrack/"
# I13 AL-2: the hook stays bash-3.2-safe (no mapfile) on a pull that changed things
mkdir -p "$FC/skills/b*eta" "$FC/scripts/hooks"; printf 'x\n' >"$FC/skills/b*eta/SKILL.md"; printf 'y\n' >"$FC/skills/b*eta/second.md"; printf '#!/bin/sh\n' >"$FC/scripts/s1.sh"; printf '#!/bin/sh\n' >"$FC/scripts/hooks/h1.sh"
git -C "$FC" add -A; git -C "$FC" -c user.email=t@t -c user.name=t commit -q -m changes
mkdir -p "$HP/bXeta" "$HP/bYeta"
printf 'enable -n mapfile readarray 2>/dev/null\n' >"$W/nomapfile.env"
(cd "$HP" && BASH_ENV="$W/nomapfile.env" CLAUDE_CONFIG_DIR="$W/cfg/.claude-claude4" CONST_DIR="$FC" PROJECT_ROOT="$HP" bash "$FC/scripts/post_update_hook.sh" >"$W/hout" 2>"$W/herr"); hrc=$?
grep -qi 'command not found' "$W/hout" "$W/herr" && bad "I13a no 'command not found' with mapfile disabled (bash < 4 stand-in)" "$(grep -i 'not found' "$W/herr" | head -1)" || ok "I13a no 'command not found' with mapfile disabled (bash < 4 stand-in)"
[ "$hrc" -ne 127 ] && grep -q 'STEP 4c' "$W/hout" && ok "I13b hook ran through to STEP 4c" || bad "I13b hook ran through to STEP 4c" "rc=$hrc"
grep -q 'Detected: 1 skill' "$W/hout" && ok "I13c 'b*eta' kept literally and its 2 change entries de-duplicated (RV1)" || bad "I13c b*eta literal + dedup" "$(grep Detected "$W/hout")"

# I23 options taking a value: missing / followed by a flag / empty / leading '-' -> exit 2,
#   nothing touched (AL5-5); control needle: the same option with a normal value works
Vm="$W/val"; mkrepo "$Vm"; P="$Vm"; EXv="$(git -C "$Vm" rev-parse --path-format=absolute --git-path info/exclude)"
vstate() { printf '%s %s' "$(tree_hash "$Vm")" "$(sha256sum <"$EXv" | cut -c1-16)"; }
vcase() { # name want-rc args... : rc and the repo + exclude state are compared before/after
  local name="$1" want="$2" v0; shift 2; v0="$(vstate)"
  check "$name" "$want $v0" "$(run claude4 "$@") $(vstate)"
}
for opt in --project-root --out-dir --identity --types --remove-alias; do
  vcase "I23 $opt with no value -> 2, untouched" 2 "$opt"
  vcase "I23 $opt followed by a flag -> 2, untouched" 2 "$opt" --dry-run
  vcase "I23 $opt empty -> 2, untouched" 2 "$opt" ''
  vcase "I23 $opt value starting with '-' -> 2, untouched" 2 "$opt" -x
done
check "I23 control needle: --types sonnet-low --dry-run with real values -> 0" 0 "$(run claude4 --types sonnet-low --dry-run)"
# I24 paths with control characters (TAB, LF, CR, 0x01, 0x7f, CR at the end) -> exit 2, nothing
#   written; out-dir symlink whose target has a CR -> refused; control needles: UTF-8 path, NUL
for cname in tab lf cr soh del crend; do
  case "$cname" in tab) c=$'\t' ;; lf) c=$'\n' ;; cr) c=$'\r' ;; soh) c=$'\001' ;; del) c=$'\177' ;; crend) c="" ;; esac
  if [ "$cname" = crend ]; then od="$Vm/ends"$'\r'; else od="$Vm/a${c}b"; fi
  vcase "I24 out-dir with $cname -> 2, nothing written" 2 --out-dir "$od"
  check "I24b out-dir with $cname was not created" 0 "$(ls -d "$od" 2>/dev/null | wc -l)"
done
Cr="$W/ctl"$'\r'"root"; mkrepo "$Cr"
check "I24 project-root with CR -> 2, nothing written" "2 0" "$(P="$Cr"; run claude4) $(ls -d "$Cr/.claude" 2>/dev/null | wc -l)"
mkdir -p "$W/crtarget"$'\r'; ln -s "$W/crtarget"$'\r' "$Vm/lnk"
check "I24 out-dir symlink to a CR path -> 2, nothing written" "2 0" "$(run claude4 --out-dir "$Vm/lnk") $(ls "$W/crtarget"$'\r' | wc -l)"
rm -f "$Vm/lnk"
run claude4 --out-dir "$Vm/ünï-é" >/dev/null; run claude4 --out-dir "$Vm/ünï-é" >/dev/null
check "I24 control needle: UTF-8 out-dir installs, 1 block after 2 runs, 0 untracked" "1 0" "$(grep -c '^# >>> agent-label-defs v2 .*ünï-é' "$EXv") $(git -C "$Vm" status --porcelain --untracked-files=all | grep -c claude4)"
run claude4 --out-dir "$Vm/nul"$'\0'"tail" >/dev/null 2>&1
check "I24 NUL needle: a NUL cannot reach argv (bash drops it; the install lands in 'nultail')" "0 1" "$(ls -d "$Vm/nul" 2>/dev/null | wc -l) $(ls -d "$Vm/nultail" 2>/dev/null | wc -l)"
P="$W/proj"

# I14 lint -----------------------------------------------------------------------------------------
bash -n "$INST" 2>/dev/null && ok "I14a bash -n clean" || bad "I14a bash -n clean"
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash "$INST" >"$W/sc" 2>&1 && ok "I14b shellcheck clean" || bad "I14b shellcheck clean" "$(head -3 "$W/sc")"; else ok "I14b shellcheck unavailable (SKIP-with-reason)"; fi
bash -n "$CONST/scripts/post_update_hook.sh" 2>/dev/null && ok "I14c post_update_hook.sh bash -n clean" || bad "I14c post_update_hook.sh bash -n clean"

# I99 the install doc states this suite's real case count (this check included) (AL5-4)
dc="$(grep -o 'test_install_agent_label_defs.sh` ([0-9]* cases' "$CONST/docs/scripts/install_agent_label_defs.md" | grep -o '[0-9]*' | head -1)"
check "I99 install doc case count equals the real total" "$((PASS + FAIL + 1))" "${dc:-none}"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
