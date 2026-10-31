#!/usr/bin/env bash
# Purpose: install_cli_agent_plugins.sh must act ONLY on link paths it can prove are its own
#   (B1 user dangling links in .gemini/.qwen/prompts kept, B2 user symlink at a generated name kept,
#   B3 every target dir containment-checked, B4 user dangling */skills/<name> link kept).
#   Tree checksums of the project sandbox and of an outside decoy prove "untouched".
# Env: none. Exit 0 all pass. One mktemp sandbox, safe_rm_rf. Does not reassign HOME.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$here/scripts/lib/safe_rm.sh"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'safe_rm_rf "$sb"' EXIT
fail=0; ck(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
tsum(){ ( cd "$1" && find . -mindepth 1 -type l -printf 'L %p -> %l\n' | LC_ALL=C sort; find . -mindepth 1 -type d | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum ) | sha256sum; }
inst(){ RC=0; HOME="$sb/home" bash "$here/scripts/install_cli_agent_plugins.sh" --no-plugin "$1" >"$sb/out" 2>&1 || RC=$?; }
mkdir -p "$sb/home" "$sb/decoy"; printf 'precious\n' > "$sb/decoy/keep.txt"
gen="$here/actions/generated/gemini"; one="$(ls "$gen"/*.toml | head -1)"; base="$(basename "$one")"

# R13_ONLY=1 runs only the round-13 section (the earlier sections spawn ~20 slow installer runs)
if [ -z "${R13_ONLY:-}" ]; then
# B1 + B4 + B2 in one project
p="$sb/p1"; mkdir -p "$p/.gemini/commands" "$p/.qwen/commands" "$p/prompts" "$p/.claude/skills" "$p/mine"
printf 'u\n' > "$p/mine/file"
ln -s "$p/gone" "$p/prompts/my_dangling.md"
ln -s "$p/gone" "$p/.gemini/commands/my_dangling.toml"
ln -s "$p/gone" "$p/.qwen/commands/my_dangling.toml"
ln -s "/x/skills/foo" "$p/.claude/skills/foo"
ln -s "$p/mine/file" "$p/.gemini/commands/$base"
inst "$p"
ck "B1 user dangling prompts link kept" "[ -L '$p/prompts/my_dangling.md' ]"
ck "B1 user dangling gemini link kept" "[ -L '$p/.gemini/commands/my_dangling.toml' ]"
ck "B1 user dangling qwen link kept" "[ -L '$p/.qwen/commands/my_dangling.toml' ]"
ck "B4 user dangling */skills/foo link kept" "[ \"\$(readlink '$p/.claude/skills/foo')\" = /x/skills/foo ]"
ck "B2 user symlink at generated name kept" "[ \"\$(readlink '$p/.gemini/commands/$base')\" = '$p/mine/file' ]"
ck "B2 user target file untouched" "[ \"\$(cat '$p/mine/file')\" = u ]"
ck "B2 refusal reported (rc non-zero or warn)" "grep -q 'left untouched' '$sb/out'"
# ours still wired + ours-dangling reaped
ck "own links wired (a different gemini cmd linked)" "[ \$(find '$p/.gemini/commands' -type l -name '*.toml' | wc -l) -gt 3 ]"
ln -s "$here/actions/generated/gemini/zz_removed.toml" "$p/.gemini/commands/zz_removed.toml"
ln -s "$here/skills/zz_removed_skill" "$p/.claude/skills/zz_removed_skill"
inst "$p"
ck "own dangling command link reaped" "[ ! -L '$p/.gemini/commands/zz_removed.toml' ]"
ck "own dangling skill link reaped" "[ ! -L '$p/.claude/skills/zz_removed_skill' ]"
ck "user dangling still kept after 2nd run" "[ -L '$p/prompts/my_dangling.md' ] && [ -L '$p/.claude/skills/foo' ]"

# B3 every target dir symlinked outside the project: nothing written outside
for d in .gemini .qwen prompts .claude; do
  q="$sb/q_${d#.}"; mkdir -p "$q"; ln -s "$sb/decoy" "$q/$d"
  before="$(tsum "$sb/decoy")"
  inst "$q"
  ck "B3 $d symlinked outside: decoy untouched" "[ '$before' = \"\$(tsum '$sb/decoy')\" ]"
  ck "B3 $d symlinked outside: rc non-zero" "[ $RC -ne 0 ]"
done
# parent-level: .gemini real dir, commands symlinked outside
q="$sb/q_sub"; mkdir -p "$q/.gemini"; ln -s "$sb/decoy" "$q/.gemini/commands"
before="$(tsum "$sb/decoy")"; inst "$q"
ck "B3 .gemini/commands symlinked outside: decoy untouched" "[ '$before' = \"\$(tsum '$sb/decoy')\" ]"
# symlink INSIDE the project is fine
q="$sb/q_in"; mkdir -p "$q/real_g"; ln -s real_g "$q/.gemini"; inst "$q"
ck "B3 .gemini symlinked inside project ok" "[ -L '$q/real_g/commands/$base' ]"
# R1: a user link to a NON-skills, NON-generated constitution file at a generated name is left untouched
q="$sb/q_r1"; mkdir -p "$q/.gemini/commands"
ln -s "$here/docs/guides/constitution_command_guide.md" "$q/.gemini/commands/$base"
inst "$q"
ck "R1 user link to other constitution file kept" "[ \"\$(readlink '$q/.gemini/commands/$base')\" = '$here/docs/guides/constitution_command_guide.md' ]"
# R4: sibling-prefix (<project>-evil) must be refused and the sibling stays empty
q="$sb/q_r4"; mkdir -p "$q" "$sb/q_r4-evil"; ln -s "../q_r4-evil" "$q/.qwen"
inst "$q"
ck "R4 .qwen -> sibling-prefix dir: sibling empty" "[ -z \"\$(ls -A '$sb/q_r4-evil')\" ]"
ck "R4 .qwen -> sibling-prefix dir: rc non-zero" "[ $RC -ne 0 ]"
# F1: .claude symlinked outside must not receive settings.json(.bak) even via the standalone prefix installer
q="$sb/q_f1"; mkdir -p "$q"; ln -s "$sb/decoy" "$q/.claude"; before="$(tsum "$sb/decoy")"
RC=0; bash "$here/scripts/install_action_prefix.sh" "$q" >/dev/null 2>&1 || RC=$?
ck "F1 standalone install_action_prefix refuses outside .claude" "[ '$before' = \"\$(tsum '$sb/decoy')\" ] && [ $RC -ne 0 ]"
ck "final: decoy + home untouched" "[ \"\$(cat '$sb/decoy/keep.txt')\" = precious ] && [ ! -e '$sb/decoy/commands' ]"

fi
# ── Round-13 additions (review of 380e692) ──
PROD="$here/scripts/install_action_prefix.sh"
pfx(){ RC=0; "${@:2}" bash "$ACT" "$1" >"$sb/out" 2>&1 || RC=$?; }
ACT="$PROD"
nojq="$sb/nojq_bin"; mkdir -p "$nojq"
for t in bash python3 dirname readlink mkdir mktemp mv cp rm ls cat sed grep stat ln basename env id tr head wc find sort uname chmod touch sleep; do
  w="$(command -v "$t" 2>/dev/null)" && ln -s "$w" "$nojq/$t"
done
# hck: like ck but counts failures in H1F (so the same case set can be replayed against mutated COPIES)
H1F=0; hck(){ if eval "$2"; then [ -n "${VERBOSE_H1-1}" ] && echo "PASS $1"; else [ -n "${VERBOSE_H1-1}" ] && echo "FAIL $1"; H1F=$((H1F+1)); fi; }
mjson(){ printf '{"outside":"%s"}\n' "$1"; }
# cases_h1 <tag>: hard links (readlink -m cannot see them) must never let an outside file be overwritten;
# outside fixtures are VALID JSON so a parse failure cannot mask a write-through; the project must also
# end up wired (rc 0 + hook present) so the rename path really ran.
cases_h1(){
  local tag="$1" mode what q out_f
  for mode in jq nojq; do
    for what in settings.json.bak settings.json.tmp settings.json; do
      q="$sb/${tag}_${mode}_${what//./_}"; mkdir -p "$q/.claude"; out_f="$sb/${tag}_out_${mode}_${what//./_}"
      mjson "$what" > "$out_f"; local want; want="$(cat "$out_f")"
      [ "$what" != settings.json ] && printf '{}\n' > "$q/.claude/settings.json"
      ln "$out_f" "$q/.claude/$what"
      if [ $mode = nojq ]; then pfx "$q" env PATH="$nojq"; else pfx "$q" env; fi
      hck "H1/$mode hard-linked $what: outside file unchanged" "[ \"\$(cat '$out_f')\" = '$want' ]"
      hck "H1/$mode hard-linked $what: project wired (rc 0 + hook)" "[ $RC -eq 0 ] && grep -q action_prefix_expand '$q/.claude/settings.json'"
    done
  done
}
cases_h1 h1
ck "H1 all cases (production script)" "[ $H1F -eq 0 ]"
# control: the no-jq (python fallback) path really works when nothing is hard-linked
q="$sb/h1_ctl"; mkdir -p "$q"; pfx "$q" env PATH="$nojq"
ck "H1 control: python fallback installs hook (rc 0)" "[ $RC -eq 0 ] && grep -q action_prefix_expand '$q/.claude/settings.json'"
# cp -al snapshot: hard-linked settings.json is NOT refused (every write is mktemp+rename); other link keeps old content
for mode in jq nojq; do
  q="$sb/cpal_$mode"; mkdir -p "$q/.claude"; printf '{"a":1}\n' > "$q/.claude/settings.json"; ln "$q/.claude/settings.json" "$sb/cpal_snap_$mode"
  if [ $mode = nojq ]; then pfx "$q" env PATH="$nojq"; else pfx "$q" env; fi
  ck "LC/$mode cp -al snapshot: rc 0, project wired" "[ $RC -eq 0 ] && grep -q action_prefix_expand '$q/.claude/settings.json'"
  ck "LC/$mode cp -al snapshot: other link keeps old content" "[ \"\$(cat '$sb/cpal_snap_$mode')\" = '{\"a\":1}' ]"
  ck "LC/$mode cp -al snapshot: warning on stderr" "grep -q 'more than one hard link' '$sb/out'"
done
# cases_mode <tag>: finding 1 (stat -L) + finding 4 (modes of new/existing files)
cases_mode(){
  local tag="$1" mode q m
  for mode in jq nojq; do
    q="$sb/${tag}_sym_$mode"; mkdir -p "$q/.claude"; printf '{}\n' > "$q/.claude/real_settings"; chmod 644 "$q/.claude/real_settings"
    ln -s real_settings "$q/.claude/settings.json"
    if [ $mode = nojq ]; then pfx "$q" env PATH="$nojq"; else pfx "$q" env; fi
    m="$(stat -L -c %a "$q/.claude/settings.json" 2>/dev/null)"
    hck "MODE/$mode symlinked settings.json -> 644 file: rc 0" "[ $RC -eq 0 ]"
    hck "MODE/$mode symlinked settings.json: not group/other-writable (got $m)" "[ '$m' = 644 ]"
    q="$sb/${tag}_new_$mode"; mkdir -p "$q"
    if [ $mode = nojq ]; then ( umask 027; pfx "$q" env PATH="$nojq" ); else ( umask 027; pfx "$q" env ); fi
    hck "MODE/$mode new settings.json follows umask 027 (640)" "[ \"\$(stat -c %a '$q/.claude/settings.json')\" = 640 ]"
    hck "MODE/$mode new .bak follows umask 027 (640)" "[ \"\$(stat -c %a '$q/.claude/settings.json.bak')\" = 640 ]"
    q="$sb/${tag}_old_$mode"; mkdir -p "$q/.claude"; printf '{}\n' > "$q/.claude/settings.json"; chmod 600 "$q/.claude/settings.json"
    if [ $mode = nojq ]; then pfx "$q" env PATH="$nojq"; else pfx "$q" env; fi
    hck "MODE/$mode existing 600 settings.json keeps 600" "[ \"\$(stat -c %a '$q/.claude/settings.json')\" = 600 ]"
  done
}
cases_mode md
ck "MODE all cases (production script)" "[ $H1F -eq 0 ]"
# finding 5: invalid JSON is refused on BOTH paths, file left unchanged
cases_invalid(){
  local tag="$1" mode body q
  for mode in jq nojq; do
    for body in 'not json {' '[1,2]'; do
      q="$sb/${tag}_bad_${mode}_${#body}"; mkdir -p "$q/.claude"; printf '%s\n' "$body" > "$q/.claude/settings.json"
      if [ $mode = nojq ]; then pfx "$q" env PATH="$nojq"; else pfx "$q" env; fi
      hck "INVALID/$mode '$body': rc non-zero" "[ $RC -ne 0 ]"
      hck "INVALID/$mode '$body': settings.json unchanged" "[ \"\$(cat '$q/.claude/settings.json')\" = '$body' ]"
    done
  done
}
cases_invalid inv
ck "INVALID all cases (production script)" "[ $H1F -eq 0 ]"
# SDR: model a path swap AFTER the readlink -m containment loop (TOCTOU) with a lying readlink that
# answers -m lexically; only the later pwd -P check (settings_dir_real) can then stop a write outside.
cases_sdr(){
  local tag="$1" fb q; fb="$sb/${tag}_fakebin"
  mkdir -p "$fb"; ln -sf "$(command -v readlink)" "$fb/real_readlink"
  printf '#!/bin/sh\nif [ "$1" = -m ]; then shift; [ "$1" = -- ] && shift; printf "%%s\\n" "$1"; exit 0; fi\nexec "$(dirname "$0")/real_readlink" "$@"\n' > "$fb/readlink"; chmod +x "$fb/readlink"
  q="$sb/${tag}_sdr"; mkdir -p "$q" "$sb/${tag}_sdr_out"; ln -s "$sb/${tag}_sdr_out" "$q/.claude"
  pfx "$q" env PATH="$fb:$PATH"
  hck "SDR lying readlink, .claude -> outside: rc non-zero" "[ $RC -ne 0 ]"
  hck "SDR lying readlink, .claude -> outside: nothing written outside" "[ -z \"\$(ls -A '$sb/${tag}_sdr_out')\" ]"
}
cases_sdr sdr
ck "SDR all cases (production script)" "[ $H1F -eq 0 ]"
# ── mutants (on COPIES in a mini constitution root; production code is never altered) ──
mkmut(){ # <name> <python-snippet operating on s> ; creates $sb/mut_<name>/scripts/...
  local r="$sb/mut_$1"; mkdir -p "$r/scripts/hooks"; cp "$here/scripts/hooks/action_prefix_expand.sh" "$r/scripts/hooks/"
  python3 - "$PROD" "$r/scripts/install_action_prefix.sh" "$2" <<'PYEOF' || return 1
import sys
s=open(sys.argv[1]).read(); orig=s
ns={'s':s}; exec(sys.argv[3],ns); s=ns['s']
if s==orig: sys.exit(3)
open(sys.argv[2],'w').write(s)
PYEOF
}
run_mut(){ # <name> ; replay all case sets against the mutant; killed if any case fails
  local name="$1"; ACT="$sb/mut_$name/scripts/install_action_prefix.sh"
  H1F=0; VERBOSE_H1=""; cases_h1 "mh_$name"; cases_mode "mm_$name"; cases_invalid "mi_$name"; cases_sdr "ms_$name"; VERBOSE_H1=1; ACT="$PROD"
  [ $H1F -gt 0 ]
}
declare -A MUT
MUT[LC]='s=s.replace("hard link; it is replaced by a new file (rename), the other links keep the old content\" >&2","hard link REFUSED\" >&2; exit 1")'
MUT[JQ]='s=s.replace("&& mv -f -- \"$tmp\" \"$settings\"; then","&& cat \"$tmp\" > \"$settings\"; then")'
MUT[PY]='s=s.replace("os.replace(tmp, path)","open(path,\"w\").write(open(tmp).read())")'
MUT[BAK]='s=s.replace("cp -f -- \"$settings\" \"$_bak\" && chmod \"$_bak_mode\" \"$_bak\" && mv -f -- \"$_bak\" \"$settings.bak\"","cp -f -- \"$settings\" \"$settings.bak\"")'
MUT[STAT]='s=s.replace("settings_mode=\"$(stat -L -c","settings_mode=\"$(stat -c")'
MUT[SDR]='s=s.replace("  \"$proj_real\"/*) ;;\n  *) echo \"install_action_prefix: $settings_dir resolves outside the project — REFUSED\" >&2; exit 1 ;;","  *) ;;")'
MUT[PYINV]='s=s.replace("sys.exit(1)\nif not isinstance","data = {}\nif not isinstance")'
for name in LC JQ PY BAK STAT PYINV SDR; do
  if mkmut "$name" "${MUT[$name]}"; then
    ck "MUTANT $name is killed by the suite" "run_mut $name"
  else
    ck "MUTANT $name could not be built (BROKEN mutant)" "false"
  fi
done
# combined LC+JQ: refusal removed AND write-through
if mkmut LCJQ "${MUT[LC]}; ${MUT[JQ]}"; then ck "MUTANT LC+JQ is killed by the suite" "run_mut LCJQ"; else ck "MUTANT LC+JQ BROKEN" "false"; fi
# M1: dangling .tmp symlink pointing outside must be refused, nothing created outside
q="$sb/m1"; mkdir -p "$q/.claude"; ln -s "$sb/m1_outside_new" "$q/.claude/settings.json.tmp"
pfx "$q" env
ck "M1 dangling .tmp -> outside: rc 1" "[ $RC -eq 1 ]"
ck "M1 dangling .tmp -> outside: nothing created outside" "[ ! -e '$sb/m1_outside_new' ]"
# M4: standalone prefix installer, .claude -> sibling-prefix dir
q="$sb/m4"; mkdir -p "$q" "$sb/m4-evil"; ln -s "../m4-evil" "$q/.claude"
pfx "$q" env
ck "M4 .claude -> sibling-prefix: sibling empty" "[ -z \"\$(ls -A '$sb/m4-evil')\" ]"
ck "M4 .claude -> sibling-prefix: rc non-zero" "[ $RC -ne 0 ]"
# M2: link_skills first check, .claude -> sibling-prefix dir
q="$sb/m2"; mkdir -p "$q" "$sb/m2-evil"; ln -s "../m2-evil" "$q/.claude"
inst "$q"
ck "M2 link_skills .claude -> sibling-prefix: sibling empty" "[ -z \"\$(ls -A '$sb/m2-evil')\" ]"
# H3: an ambient HELIX_ACTION_OUT_ROOT must not redirect generated output
q="$sb/h3"; mkdir -p "$q"; RC=0
HOME="$sb/home" HELIX_ACTION_OUT_ROOT="$sb/h3_redirect" bash "$here/scripts/install_cli_agent_plugins.sh" --no-plugin "$q" >"$sb/out" 2>&1 || RC=$?
ck "H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (installer)" "[ ! -e '$sb/h3_redirect' ]"
RC=0; HELIX_ACTION_OUT_ROOT="$sb/h3_redirect2" bash "$here/scripts/install_action_prefix.sh" "$q" >/dev/null 2>&1 || RC=$?
ck "H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix)" "[ ! -e '$sb/h3_redirect2' ]"
exit $fail
