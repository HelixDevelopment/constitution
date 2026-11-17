#!/usr/bin/env bash
# test_history_read_time_hiding.sh -- tests that the two history secret scans read what git would
# otherwise hide at read time (CON-453, CON-438 class):
#   scripts/gitleaks/gitleaks_run_scan.sh   (S: gitleaks detect on the working repository)
#   scripts/security/history_secret_scan.sh (H: gitleaks git on a bare mirror of a URL)
#
# Purpose: git applies diff attributes (-diff, binary, a diff driver with binary=true or a
# textconv) to `git log -p`, so a secret in such a path is shown as "Binary files differ" or as
# converted text and the scanner never sees it. The attribute can come from the scanned history
# (a committed .gitattributes), from .git/info/attributes, or from the caller (core.attributesFile,
# $XDG_CONFIG_HOME/git/attributes, GIT_CONFIG_PARAMETERS, GIT_ATTR_SOURCE). Grafts and a
# .git/shallow file stop the history walk; a secret that exists only in a merge commit is not
# printed without -m; and gitleaks reports 0 leaks with exit 0 when its git fails. Before the fix
# each of these gave exit 0 and the secret missing (a false PASS). Cases:
#   S0 precondition: a committed -diff attribute hides the secret from `git log -p`, --text shows it
#   S1 control (no attribute): found          S2 committed .gitattributes -diff: found
#   S3 committed `binary` macro: found       S4 diff driver textconv in repo config: found
#   S5 .git/info/attributes -diff: found     S6 caller core.attributesFile (GIT_CONFIG_GLOBAL): found
#   S7 caller $XDG_CONFIG_HOME/git/attributes: found
#   S8 caller GIT_ATTR_SOURCE naming a tree with -diff: found
#   S9 caller GIT_CONFIG_PARAMETERS core.attributesFile: found
#   S10 caller `-- --log-opts "--all"` (two words) on the -diff repo: found
#   S11 caller `-- --log-opts=--all` (one word) on the -diff repo: found
#   S12 secret only in a merge commit: found  S13 .git/info/grafts hides the secret commit: found
#   S14 .git/shallow names a commit whose parents exist: found
#   S15 a real shallow clone: exit 3 INCONCLUSIVE, never PASS
#   S16 negative control: exit 0, zero findings
#   S17 `-- --log-opts` with no value: exit 2
#   S18 the self-check leaves no glrs_selfcheck.* directory behind
#   S19 (fake only) a scanner that ignores --log-opts: exit 3 INCONCLUSIVE, never PASS
#   S20-S22 (fake only) a scanner that drops only --text / only --no-textconv / only -m:
#       exit 3 INCONCLUSIVE (each control needle guards its own option)
#   H1 control: found                         H2 caller core.attributesFile with the secret path: found
#   H3 caller GIT_ATTR_SOURCE: found          H4 caller $XDG_CONFIG_HOME/git/attributes: found
#   H5 caller diff driver textconv (global config) + committed diff=: found
#   H6 source repository with .git/info/grafts: found
#   H7 shallow source: exit 3 BLIND           H8 negative control: exit 0
#   H9/H10 (fake only) a scanner that drops only --text / only --no-textconv: exit 3 BLIND
# Scanner: by default the fakes tests/security/fixtures/fake_gitleaks_detect.py (S) and
# fake_gitleaks.py (H) (gate-logic only, §11.4.289). With GLRS_GITLEAKS=/path/to/gitleaks the REAL
# binary is used for both (live evidence); S19 and H9 are then SKIP lines (they need a scanner
# that misbehaves on purpose).
# Fabricated values are random per run and built with python3; output never prints them.
#
# Usage: bash tests/security/test_history_read_time_hiding.sh
#        GLRS_SCRIPT=/path/to/gitleaks_run_scan.sh HSS_SCRIPT=/path/to/history_secret_scan.sh bash ...
#        GLRS_GITLEAKS=/path/to/real/gitleaks bash ...   (live run)
#        SEC_TEST_FAILFAST=1 stops at the first failing case
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${GLRS_SCRIPT:-$here/scripts/gitleaks/gitleaks_run_scan.sh}"
HSS="${HSS_SCRIPT:-$here/scripts/security/history_secret_scan.sh}"
FIX="$here/tests/security/fixtures"
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
[ -f "$SCRIPT" ] && [ -f "$HSS" ] || { echo "env: script not found" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
HSS="$(cd "$(dirname "$HSS")" && pwd)/$(basename "$HSS")"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/bin" "$tmp/tmpdir" "$tmp/scratch"
if [ -n "${GLRS_GITLEAKS:-}" ]; then
  [ -x "$GLRS_GITLEAKS" ] || { echo "env: GLRS_GITLEAKS is not executable: $GLRS_GITLEAKS" >&2; exit 2; }
  ln -s "$GLRS_GITLEAKS" "$tmp/bin/gitleaks"; HGL="$GLRS_GITLEAKS"; MODE=real
else
  printf '#!/usr/bin/env bash\nexec python3 -I %q "$@"\n' "$FIX/fake_gitleaks_detect.py" > "$tmp/bin/gitleaks"
  printf '#!/usr/bin/env bash\nexec python3 -I %q "$@"\n' "$FIX/fake_gitleaks.py" > "$tmp/hgl"
  chmod +x "$tmp/bin/gitleaks" "$tmp/hgl"; HGL="$tmp/hgl"; MODE=fake
fi
echo "scanner: $MODE"
# A clean, hermetic git configuration for building the fixtures; each case adds its own caller state.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/empty.cfg" XDG_CONFIG_HOME="$tmp/xdg_none"
: > "$tmp/empty.cfg"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
export GIT_AUTHOR_DATE=2001-01-01T00:00:00Z GIT_COMMITTER_DATE=2001-01-01T00:00:00Z
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
skip(){ echo "SKIP $1"; }
tok(){ python3 -I -c 'import secrets,string;a=string.ascii_letters+string.digits;print("gh"+"p_"+"".join(secrets.choice(a) for _ in range(36)))'; }

# mk REPO [ATTRLINE] : base commit, optional committed .gitattributes, secret s.env added then removed.
# Sets SEC to the secret of that repository.
mk(){
  local r=$1 a=${2:-}
  git init -q -b main "$r"; echo base > "$r/a.txt"; git -C "$r" add .; git -C "$r" commit -qm base
  if [ -n "$a" ]; then printf '%s\n' "$a" > "$r/.gitattributes"; git -C "$r" add .; git -C "$r" commit -qm attrs; fi
  SEC=$(tok); printf 'TOKEN=%s\n' "$SEC" > "$r/s.env"; git -C "$r" add .; git -C "$r" commit -qm secret
  git -C "$r" rm -q s.env; git -C "$r" commit -qm drop
}
tree_attr(){ # REPO LINE -> tree id holding .gitattributes with LINE
  local b; b=$(printf '%s\n' "$2" | git -C "$1" hash-object -w --stdin); printf '100644 blob %s\t.gitattributes\n' "$b" | git -C "$1" mktree
}
scan(){ # REPO [env assignments...] [-- extra args] -> RC, FJ
  local r=$1; shift; local -a ev=() ex=()
  while [ $# -gt 0 ]; do if [ "$1" = -- ]; then shift; ex=("$@"); break; fi; ev+=("$1"); shift; done
  ( cd "$tmp" && env TMPDIR="$tmp/tmpdir" "${ev[@]}" PATH="$tmp/bin:$PATH" bash "$SCRIPT" "$r" ${ex[@]+-- "${ex[@]}"} ) > "$tmp/out" 2> "$tmp/err"; RC=$?
  FJ=$(sed -n 's/^ *\[evidence: \(.*\)\]$/\1/p' "$tmp/out" | tail -1); FJ=${FJ:+$FJ/findings.json}
}
has(){ [ -n "$FJ" ] && [ -f "$FJ" ] && jq -e --arg v "$1" 'map(.Secret) | index($v) != null' "$FJ" >/dev/null 2>&1; }
count(){ if [ -n "$FJ" ] && [ -s "$FJ" ]; then jq 'length' "$FJ"; else echo 0; fi; }
show(){ sed 's/^/     | /' "$tmp/out" "$tmp/err" | tail -8; }
found_case(){ # LABEL REPO [scan args...] : expects exit 1 with SEC in the report
  local l=$1 r=$2 s=$SEC; shift 2; scan "$r" "$@"
  if [ "$RC" = 1 ] && has "$s"; then ok "$l: secret found (exit 1)"; else nok "$l: secret not found (rc=$RC, findings=$(count))"; show; fi
}

# ---- S: gitleaks_run_scan.sh ----------------------------------------------------------------
mk "$tmp/s_diff" '*.env -diff'; S_DIFF_SEC=$SEC
git -C "$tmp/s_diff" log -p --all > "$tmp/l0"; git -C "$tmp/s_diff" log -p --all --text > "$tmp/l1"
if ! grep -qF "$S_DIFF_SEC" "$tmp/l0" && grep -qF "$S_DIFF_SEC" "$tmp/l1"; then
  ok "S0 precondition: a committed -diff attribute hides the secret from git log -p; --text shows it"
else nok "S0 precondition: the attribute does not hide the secret (the cases below prove nothing)"; fi
mk "$tmp/s_ctl"; found_case "S1 control" "$tmp/s_ctl"
SEC=$S_DIFF_SEC; found_case "S2 committed .gitattributes -diff" "$tmp/s_diff"
mk "$tmp/s_bin" '*.env binary'; found_case "S3 committed binary macro" "$tmp/s_bin"
mk "$tmp/s_tcv" '*.env diff=hsst'; git -C "$tmp/s_tcv" config diff.hsst.textconv true
found_case "S4 diff driver textconv in repo config" "$tmp/s_tcv"
mk "$tmp/s_info"; printf '*.env -diff\n' > "$tmp/s_info/.git/info/attributes"; found_case "S5 .git/info/attributes" "$tmp/s_info"
printf 's.env -diff\n' > "$tmp/caller.attr"; printf '[core]\n\tattributesFile = %s\n' "$tmp/caller.attr" > "$tmp/caller.cfg"
mk "$tmp/s_gaf"; found_case "S6 caller core.attributesFile" "$tmp/s_gaf" GIT_CONFIG_GLOBAL="$tmp/caller.cfg"
mkdir -p "$tmp/xdg/git"; printf 's.env -diff\n' > "$tmp/xdg/git/attributes"
mk "$tmp/s_xdg"; found_case "S7 caller XDG attributes" "$tmp/s_xdg" XDG_CONFIG_HOME="$tmp/xdg"
mk "$tmp/s_gas"; t=$(tree_attr "$tmp/s_gas" 's.env -diff'); found_case "S8 caller GIT_ATTR_SOURCE" "$tmp/s_gas" GIT_ATTR_SOURCE="$t"
mk "$tmp/s_gcp"; found_case "S9 caller GIT_CONFIG_PARAMETERS" "$tmp/s_gcp" "GIT_CONFIG_PARAMETERS='core.attributesFile'='$tmp/caller.attr'"
SEC=$S_DIFF_SEC; found_case "S10 caller --log-opts (two words)" "$tmp/s_diff" -- --log-opts "--all"
SEC=$S_DIFF_SEC; found_case "S11 caller --log-opts= (one word)" "$tmp/s_diff" -- --log-opts=--all
r="$tmp/s_merge"; git init -q -b main "$r"; echo a > "$r/a.txt"; git -C "$r" add .; git -C "$r" commit -qm base
git -C "$r" checkout -q -b side; echo b > "$r/b.txt"; git -C "$r" add .; git -C "$r" commit -qm side
git -C "$r" checkout -q main; echo c > "$r/c.txt"; git -C "$r" add .; git -C "$r" commit -qm c
git -C "$r" merge -q --no-ff --no-commit side >/dev/null; SEC=$(tok); printf 'TOKEN=%s\n' "$SEC" > "$r/s.env"; git -C "$r" add .; git -C "$r" commit -qm merge
git -C "$r" rm -q s.env; git -C "$r" commit -qm drop
found_case "S12 secret only in a merge commit" "$r"
mk "$tmp/s_graft"; git -C "$tmp/s_graft" rev-parse HEAD > "$tmp/s_graft/.git/info/grafts"; found_case "S13 .git/info/grafts" "$tmp/s_graft"
mk "$tmp/s_fshal"; git -C "$tmp/s_fshal" rev-parse HEAD > "$tmp/s_fshal/.git/shallow"; found_case "S14 .git/shallow with parents present" "$tmp/s_fshal"
mk "$tmp/s_src"; git clone -q --depth 1 "file://$tmp/s_src" "$tmp/s_rshal"
scan "$tmp/s_rshal"
if [ "$RC" = 3 ] && grep -q INCONCLUSIVE "$tmp/out"; then ok "S15 real shallow clone: exit 3 INCONCLUSIVE"; else nok "S15 real shallow clone: rc=$RC (expected 3)"; show; fi
git init -q -b main "$tmp/s_neg"; echo plain > "$tmp/s_neg/p.txt"; git -C "$tmp/s_neg" add .; git -C "$tmp/s_neg" commit -qm neg
scan "$tmp/s_neg"
if [ "$RC" = 0 ] && [ "$(count)" = 0 ]; then ok "S16 negative control: exit 0, zero findings"; else nok "S16 negative control: rc=$RC findings=$(count)"; show; fi
scan "$tmp/s_ctl" -- --log-opts
if [ "$RC" = 2 ]; then ok "S17 --log-opts with no value: exit 2"; else nok "S17 --log-opts with no value: rc=$RC"; show; fi
if [ -z "$(find "$tmp/tmpdir" -maxdepth 1 -name 'glrs_selfcheck.*' -print -quit)" ]; then ok "S18 no glrs_selfcheck.* directory left behind"; else nok "S18 a glrs_selfcheck.* directory was left behind"; fi
if [ "$MODE" = fake ]; then
  SEC=$S_DIFF_SEC; scan "$tmp/s_diff" FAKE_GLD_IGNORE_LOGOPTS=1
  if [ "$RC" = 3 ] && grep -q INCONCLUSIVE "$tmp/out"; then ok "S19 scanner ignoring --log-opts: exit 3 INCONCLUSIVE"; else nok "S19 scanner ignoring --log-opts: rc=$RC (expected 3)"; show; fi
  k=19
  for w in --text --no-textconv -m; do
    k=$((k + 1))
    scan "$tmp/s_ctl" FAKE_GLD_STRIP="$w"
    if [ "$RC" = 3 ] && grep -q INCONCLUSIVE "$tmp/out"; then ok "S$k scanner dropping only $w: exit 3 INCONCLUSIVE"; else nok "S$k scanner dropping only $w: rc=$RC (expected 3)"; show; fi
  done
else skip "S19-S22 need a scanner that misbehaves on purpose (fake only)"; fi

# ---- H: history_secret_scan.sh ----------------------------------------------------------------
hscan(){ # REPO-URL [env assignments...] -> HRC, HOUT
  local u=$1; shift; HOUT="$tmp/scratch/out_$n.tsv"
  env "$@" SCRATCH="$tmp/scratch" OUT="$HOUT" GITLEAKS="$HGL" bash "$HSS" "$u" > "$tmp/hout" 2> "$tmp/herr"; HRC=$?
}
hfound(){ [ -f "$HOUT" ] && grep -q $'\ts.env:' "$HOUT"; }
hshow(){ sed 's/^/     | /' "$tmp/hout" "$tmp/herr" | tail -6; }
hfound_case(){ # LABEL REPO [env...]
  local l=$1 r=$2; shift 2; hscan "$r" "$@"
  if [ "$HRC" = 1 ] && hfound; then ok "$l: secret found (exit 1)"; else nok "$l: secret not found (rc=$HRC)"; hshow; fi
}
hfound_case "H1 control" "$tmp/s_ctl"
hfound_case "H2 caller core.attributesFile" "$tmp/s_gaf" GIT_CONFIG_GLOBAL="$tmp/caller.cfg"
t=$(tree_attr "$tmp/s_gas" 's.env -diff'); hfound_case "H3 caller GIT_ATTR_SOURCE" "$tmp/s_gas" GIT_ATTR_SOURCE="$t"
hfound_case "H4 caller XDG attributes" "$tmp/s_xdg" XDG_CONFIG_HOME="$tmp/xdg"
mk "$tmp/h_tcv" 's.env diff=hsst'; printf '[diff "hsst"]\n\ttextconv = true\n' > "$tmp/tcv.cfg"
hfound_case "H5 caller textconv driver" "$tmp/h_tcv" GIT_CONFIG_GLOBAL="$tmp/tcv.cfg"
hfound_case "H6 source with .git/info/grafts" "$tmp/s_graft"
hscan "$tmp/s_rshal"
if [ "$HRC" = 3 ] && grep -q shallow "$tmp/herr"; then ok "H7 shallow source: exit 3 BLIND"; else nok "H7 shallow source: rc=$HRC (expected 3)"; hshow; fi
hscan "$tmp/s_neg"
if [ "$HRC" = 0 ]; then ok "H8 negative control: exit 0"; else nok "H8 negative control: rc=$HRC"; hshow; fi
if [ "$MODE" = fake ]; then
  hscan "$tmp/s_ctl" FAKE_GITLEAKS_STRIP=--text
  if [ "$HRC" = 3 ] && grep -q 'the -diff attribute needle' "$tmp/herr"; then ok "H9 scanner dropping only --text: exit 3 BLIND"; else nok "H9 scanner dropping only --text: rc=$HRC (expected 3)"; hshow; fi
  hscan "$tmp/s_ctl" FAKE_GITLEAKS_STRIP=--no-textconv
  if [ "$HRC" = 3 ] && grep -q 'the textconv needle' "$tmp/herr"; then ok "H10 scanner dropping only --no-textconv: exit 3 BLIND"; else nok "H10 scanner dropping only --no-textconv: rc=$HRC (expected 3)"; hshow; fi
else skip "H9/H10 need a scanner that misbehaves on purpose (fake only)"; fi
echo "RESULT: $((n-bad))/$n passed (scanner: $MODE)"
[ "$bad" -eq 0 ]
