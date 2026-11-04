#!/usr/bin/env bash
# cm_agent_type_label_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-AGENT-TYPE-LABEL (§11.4.182 / §11.4.231(F)).
#
# Purpose : prove the gate is NOT a bluff — it PASSes the real toolchain and
#   FAILs every planted regression of the generator / installer / hook:
#     M0  clean copy                                   -> PASS (golden-FALSE)
#     M1  non-idempotent generator ($RANDOM in body)    -> FAIL
#     M2  generator overwrites hand-made files          -> FAIL
#     M3  --check always exits 0 (blind drift check)    -> FAIL
#     M4  frontmatter effort disagrees with the name    -> FAIL
#     M5  colour outside the supported set (data file)  -> FAIL
#     M6  hook skips the agent-type check               -> FAIL
#     M7  hook ignores AGENT_TYPE_LABEL_ENFORCE         -> FAIL
#     M8  hook also flags specialist/plugin types       -> FAIL
#     M9  hook counts hand-made (unmarked) types        -> FAIL
#     M10 installer prunes hand-made files              -> FAIL
#     M11 generator silently drops the `max` effort     -> FAIL
#     M12 hook forgets the audited bypass reason        -> FAIL
#     R1  reviewer text moved from opus-xhigh to opus-max -> FAIL  (review 2026-11-03 M4)
#     R2  hook drops the cross-track detection             -> FAIL  (review 2026-11-03 M7)
#     R3  hook ignores the call's model/effort parameters  -> FAIL  (F2)
#     R4  hook WARN payload built without JSON escaping    -> FAIL  (F7)
#     R5  installer prunes declared tracks outside filter  -> FAIL  (F4)
#     R6  installer accepts a user-level config dir        -> FAIL  (F1)
#     R7  installer does not resolve symlinks of user config dirs -> FAIL (R2-1)
#     R8  installer allows an out-dir that contains a user config dir -> FAIL (R2-3, ME)
#     R9  installer prunes undeclared files outside the --models filter -> FAIL (R2-3, MA)
#     R10 installer allows a project root equal to / above HOME -> FAIL (R2-3, MF)
#     R11 installer prunes a declared-but-unresolvable track -> FAIL (R2-2)
#     R12 installer prunes with no usable config -> FAIL (R2-2)
#     R13 installer ignores the passwd home when HOME is empty -> FAIL (R2-1)
#     RV7 R20-R22 RV5 round-5 canonicaliser / per-process link / cross-check / un-enterable root -> FAIL (R5-1..R5-3)
#     RM3 RM4 R23-R32 round-6 partial-prefix cross-check / OLDPWD / CDPATH / undecidable lstat / raw out-dir -> FAIL (R6-1..R6-3)
#     X1-X4 X6 S1-S11 round-7 boundaries / byte-exact captures / option-like --classify / failing sha256 -> FAIL (R7-1..R7-5)
#     E2  an ambient AGENT_TYPE_LABEL_AGENTS_DIR does not change the verdict (R2-4)
#     E1  an ambient HP in the caller's environment does not change the verdict (F3)
#   plus gate-level cases on the dispatch-log audit (warn vs enforce) and a
#   removed-doc / removed-script case.
# Usage   : bash scripts/gates/cm_agent_type_label_mutation_test.sh
# Side-effects: temp tree under ${TMPDIR:-/tmp}, removed on exit; the real
#   scripts are only READ (copied), never modified.
# Exit    : 0 every case had the expected verdict · 1 otherwise · 2 env error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONST="$(cd "$HERE/../.." && pwd -P)"
GATE="$HERE/cm_agent_type_label.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/cm_atl_mut.XXXXXX")"
trap 'rm -rf "$T"' EXIT
rc=0
note() { echo "$@"; }
expect() { # want(pass|fail) desc cmd...
  local want="$1" desc="$2"; shift 2
  if "$@" >"$T/last.out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then note "OK    $desc (gate ${got}ed as required)"; else note "META FAIL: $desc — gate ${got}ed, wanted $want"; sed 's/^/        | /' "$T/last.out" | tail -8; rc=1; fi
}

fresh_tree() { # name -> $T/name/scripts/{multitrack,hooks,gates}
  local d="$T/$1"; mkdir -p "$d/scripts/gates" "$d/docs/scripts"
  cp -r "$CONST/scripts/multitrack" "$d/scripts/multitrack"
  cp -r "$CONST/scripts/hooks" "$d/scripts/hooks"
  cp "$GATE" "$d/scripts/gates/"
  cp "$CONST/docs/scripts/gen_agent_label_defs.md" "$CONST/docs/scripts/install_agent_label_defs.md" "$CONST/docs/scripts/guard-track-branch-label.md" "$d/docs/scripts/" 2>/dev/null
  echo "$d"
}
gate_in() { # tree -> runs the gate copy living inside that tree
  bash "$1/scripts/gates/cm_agent_type_label.sh" --quiet
}
mutate() { # tree file python-snippet-old python-snippet-new
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[2], sys.argv[3].encode().decode('unicode_escape'), sys.argv[4].encode().decode('unicode_escape')
s = open(path).read()
if old not in s:
    sys.stderr.write("MUTANT-NOT-APPLIED: %r not found in %s\n" % (old, path)); sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-AGENT-TYPE-LABEL"

D=$(fresh_tree m0);  expect pass "M0 clean copy of the real toolchain" gate_in "$D"

D=$(fresh_tree m1); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  hash="$({' '  body="$body #$RANDOM"\n  hash="$({' || rc=1
expect fail "M1 non-idempotent generator" gate_in "$D"

D=$(fresh_tree m2); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then' 'if false; then' || rc=1
expect fail "M2 generator overwrites hand-made files" gate_in "$D"

D=$(fresh_tree m3); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '[ "$ndrift" -eq 0 ] && exit 0 || exit 1' 'exit 0' || rc=1
expect fail "M3 --check is blind to drift" gate_in "$D"

D=$(fresh_tree m4); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '"$m" "$e" "$color")"' '"$m" "medium" "$color")"' || rc=1
expect fail "M4 frontmatter effort disagrees with the type name" gate_in "$D"

D=$(fresh_tree m5); sed -i 's/^1\tblue$/1\tmagenta/;s/^\*\tyellow$/*\tmagenta/' "$D/scripts/multitrack/agent_label_colors.tsv"
expect fail "M5 colour outside the supported set" gate_in "$D"

D=$(fresh_tree m6); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    _type_check\n    exit $?' '    exit 0' || rc=1
expect fail "M6 hook skips the agent-type check" gate_in "$D"

D=$(fresh_tree m7); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '"${AGENT_TYPE_LABEL_ENFORCE:-0}" == "1"' '"0" == "1"' || rc=1
expect fail "M7 hook ignores AGENT_TYPE_LABEL_ENFORCE" gate_in "$D"

D=$(fresh_tree m8); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    *) return 0 ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' '    *) reason="specialist" ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' || rc=1
expect fail "M8 hook flags specialist/plugin types" gate_in "$D"

D=$(fresh_tree m9); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" "    grep -q '^<!-- generated-by: gen_agent_label_defs\\\\.sh v1 ' \"\$f\" 2>/dev/null || continue\n" '' || rc=1
expect fail "M9 hook counts hand-made types as generated" gate_in "$D"

D=$(fresh_tree m10); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '      genuine)\n' '      genuine|handmade)\n' || rc=1
expect fail "M10 installer prunes hand-made files" gate_in "$D"

D=$(fresh_tree m11); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  for e in "${EFFORT_LIST[@]}"; do\n    f=' '  for e in "${EFFORT_LIST[@]}"; do\n    [ "$e" = max ] && continue\n    f=' || rc=1
expect fail "M11 generator silently drops the max effort" gate_in "$D"

D=$(fresh_tree m12); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS:-}" ]]; then' '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS+x}" ]]; then' || rc=1
expect fail "M12 empty bypass reason bypasses" gate_in "$D"

D=$(fresh_tree r1); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'if [ "$m" = opus ] && [ "$e" = xhigh ]; then' 'if [ "$m" = opus ] && [ "$e" = max ]; then' || rc=1
expect fail "R1 reviewer-substrate body moved from opus-xhigh to opus-max" gate_in "$D"

D=$(fresh_tree r2); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '      if [[ "$nmatch" != "$ltrack" ]]; then' '      if false; then' || rc=1
expect fail "R2 hook drops the cross-track detection" gate_in "$D"

D=$(fresh_tree r3); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '        pmodel="$(json_field .tool_input.model)"; peffort="$(json_field .tool_input.effort)"' '        pmodel=""; peffort=""' || rc=1
expect fail "R3 hook ignores the call's model/effort parameters" gate_in "$D"

D=$(fresh_tree r4); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '"$(_json_esc "$msg")"' '"$msg"' || rc=1
expect fail "R4 WARN payload without JSON escaping" gate_in "$D"

D=$(fresh_tree r5); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${DECLARED[${BASH_REMATCH[1]}]:-}" ] && continue\n' '' || rc=1
mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] || continue' '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] && [ -n "${DECLARED[${BASH_REMATCH[1]}]:-}" ] && continue' || rc=1
expect fail "R5 installer prunes a declared track's files outside the --models filter" gate_in "$D"

D=$(fresh_tree r6); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'refuse6() { echo' 'refuse6() { return 0; echo' || rc=1
expect fail "R6 installer accepts a user-level config dir" gate_in "$D"

D=$(fresh_tree r7); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'add_cfg() { local _cc=""; add_uniq USERCFG "$1"; canon_to _cc "$1"; add_uniq USERCFG "$_cc"; }' 'add_cfg() { add_uniq USERCFG "$1"; }' || rc=1
expect fail "R7 installer does not resolve symlinked user config dirs" gate_in "$D"

D=$(fresh_tree r8); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  under "$c" "$od_c" && refuse6' '  false && refuse6' || rc=1
expect fail "R8 installer allows an out-dir containing a user config dir" gate_in "$D"

D=$(fresh_tree r9); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] || continue' '    true' || rc=1
expect fail "R9 installer prunes undeclared files outside the --models filter" gate_in "$D"

D=$(fresh_tree r10); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  under "$h" "$pr_c" && refuse6' '  false && refuse6' || rc=1
expect fail "R10 installer allows a project root that is / above HOME" gate_in "$D"

D=$(fresh_tree r11); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${UNRESOLVED[$((10#$tnum))]:-}" ] && continue' '    true' || rc=1
expect fail "R11 installer prunes a declared-but-unresolvable track" gate_in "$D"

D=$(fresh_tree r12); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'if [ "$cfg_ok" -eq 1 ] && [ -d "$out_dir" ]; then' 'if [ -d "$out_dir" ]; then' || rc=1
expect fail "R12 installer prunes with no usable config" gate_in "$D"

# R14: the root is guarded by TWO independent layers (the explicit '[ "$t" = / ]' check and under()'s root-ancestor
# rule, which also makes '/' an ancestor of every system dir); both are removed together, one alone is redundant.
D=$(fresh_tree r14); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ "$2" = / ] && return 0; ' '' || rc=1
mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  [ "$t" = / ] && refuse6' '  false && refuse6' || rc=1
expect fail "R14 the filesystem root is not refused (--out-dir / written)" gate_in "$D"

D=$(fresh_tree r15); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    under "$t" "$sd" && refuse6' '    false && refuse6' || rc=1
expect fail "R15 system directories are not refused as out-dir" gate_in "$D"

D=$(fresh_tree r16); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ "$1" = "$2" ] && return 0; ' '' || rc=1
expect fail "R16 under() loses its equality branch (out-dir equal to a user config dir)" gate_in "$D"

D=$(fresh_tree x3); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '{ [ -e "$c" ] || [ -L "$c" ]; }' '[ -e "$c" ]' || rc=1
expect fail "X3 the ~/.claude-* glob ignores dangling symlinks" gate_in "$D"

D=$(fresh_tree x4); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'else UNRESOLVED["$((10#$tn))"]=1; echo "SKIP     ${tid}: branch' 'else UNRESOLVED["$tn"]=1; echo "SKIP     ${tid}: branch' || rc=1
expect fail "X4 UNRESOLVED keyed by the raw track digits (007 vs 7)" gate_in "$D"

D=$(fresh_tree x5); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'canon_to _cz "$HOME"; add_uniq HOMES "$_cz"; ' '' || rc=1
expect fail "X5 HOME is not canonicalised" gate_in "$D"

D=$(fresh_tree x7); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'if [ "${#HOMES[@]}" -eq 0 ] && [ "$do_check" -eq 0 ]; then' 'if false; then' || rc=1
expect fail "X7 the no-resolvable-home refusal is disabled" gate_in "$D"

# R17: the round-4 canonicaliser (realpath -m with a raw-path fallback) is restored
D=$(fresh_tree r17); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  [ -n "$1" ] || return 1\n  case "$1" in' '  printf "%s\\n" "$(realpath -m -- "$1" 2>/dev/null || printf "%s" "$1")"; return 0\n  case "$1" in' || rc=1
expect fail "R17 canon() falls back to the raw path when realpath -m is unavailable (R4-1)" gate_in "$D"
D=$(fresh_tree r18); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '..) cur="${cur%/*}"; [ -n "$cur" ] || cur=/; continue ;;' '..) continue ;;' || rc=1
expect fail "R18 canon() ignores '..'" gate_in "$D"
D=$(fresh_tree r19); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  exact_out canon "$2" || _crc=$?; _cv="$EXACT"' '  exact_out canon "$2" || EXACT="$2"; _cv="$EXACT"' || rc=1
expect fail "R19 an uncanonicalisable path is used raw instead of refused (fail open)" gate_in "$D"
# review round 5 (R5-1..R5-3)
D=$(fresh_tree rv7); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '      ..) cur="${cur%/*}"; [ -n "$cur" ] || cur=/; continue ;;\n' '      ..) cur="${cur%/*}"; [ -n "$cur" ] || cur=/; continue ;;\n      *) case "$rest" in ..|../*) rest="${rest#..}"; rest="${rest#/}"; continue ;; esac ;;\n' || rc=1
expect fail "RV7 canon() resolves '..' lexically before the symlink in front of it (R5-2)" gate_in "$D"
D=$(fresh_tree r20); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '      case "$t" in /proc|/proc/*|/dev/fd|/dev/stdin|/dev/stdout|/dev/stderr) return 2 ;; esac\n' '' || rc=1
expect fail "R20 canon() follows per-process links under /proc and /dev/fd (R5-1)" gate_in "$D"
D=$(fresh_tree r21); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  exact_out canon "$p" || return 1; cp="$EXACT"\n  [ "$kp" = "$cp" ]' '  return 0' || rc=1
expect fail "R21 canon_kcheck() always agrees (kernel cross-check blind, R5-1)" gate_in "$D"
D=$(fresh_tree r22); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  canon_kcheck "$2" "$_cv" || refuse6' '  true || refuse6' || rc=1
expect fail "R22 canon_to() never calls the kernel cross-check (R5-1)" gate_in "$D"
D=$(fresh_tree rv5); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ "$pr_unentered" -eq 0 ] || die2 "project root \x27$project_root\x27 cannot be entered"\n' '' || rc=1
expect fail "RV5 an un-enterable project root proceeds instead of exit 2 (R5-3)" gate_in "$D"
# review round 6 (R6-1..R6-3): reviewer mutants RM3/RM4 and one mutant per new guard
I6="scripts/multitrack/install_agent_label_defs.sh"
D=$(fresh_tree rm3); mutate "$D" "$D/$I6" '  exact_out canon "$p" || return 1; cp="$EXACT"\n' '  [ "$p" = "$1" ] || return 0\n  exact_out canon "$p" || return 1; cp="$EXACT"\n' || rc=1
expect fail "RM3 canon_kcheck() checks only when the WHOLE path is enterable (R6-3)" gate_in "$D"
D=$(fresh_tree rm4); mutate "$D" "$D/$I6" '*/*) p="${p%/*}"; [ -n "$p" ] || p=/ ;;' '*/*) p="${p%%/*}"; [ -n "$p" ] || p=/ ;;' || rc=1
expect fail "RM4 canon_kcheck() jumps straight to the first component (R6-3)" gate_in "$D"
D=$(fresh_tree r23); mutate "$D" "$D/$I6" '*) cdp="./$p" ;;' '*) cdp="$p" ;;' || rc=1
expect fail "R23 canon_kcheck() enters a relative prefix bare ('-' = OLDPWD, R6-1/R6-2)" gate_in "$D"
D=$(fresh_tree r24); mutate "$D" "$D/$I6" '    [ "${#t}" -lt "$pmax" ] || return 1' '    true' || rc=1
expect fail "R24 canon() walks a path of PATH_MAX or more lexically (R6-1)" gate_in "$D"
D=$(fresh_tree r25); mutate "$D" "$D/$I6" '    elif [ -d "$cur" ] && [ ! -x "$cur" ]; then\n      return 1' '    elif false; then\n      return 1' || rc=1
expect fail "R25 canon() walks a component it cannot lstat (EACCES) lexically (R6-1)" gate_in "$D"
D=$(fresh_tree r26); mutate "$D" "$D/$I6" '    if [ "$cur" != / ] && [ -e "$cur" ] && [ ! -d "$cur" ]; then return 1; fi' '    true' || rc=1
expect fail "R26 canon() walks past an existing non-directory (ENOTDIR)" gate_in "$D"
D=$(fresh_tree r27); mutate "$D" "$D/$I6" '    [ "${#comp}" -le "$nmax" ] || return 1' '    true' || rc=1
expect fail "R27 canon() keeps a component longer than NAME_MAX" gate_in "$D"
D=$(fresh_tree r28); mutate "$D" "$D/$I6" '*) return 1 ;; esac\n  pmax="$(command getconf' '*) : ;; esac\n  pmax="$(command getconf' || rc=1
expect fail "R28 canon() accepts a path containing a newline" gate_in "$D"
D=$(fresh_tree r29); mutate "$D" "$D/$I6" 'unset CDPATH   #' ': CDPATH   #' || rc=1
# R29 is EQUIVALENT since round 7: every cd in the installer is CDPATH=''-prefixed (cdpwd), absolute, or ./-prefixed,
# and the sourced multitrack_config.sh reaches its only cd solely when MT_REPO_ROOT is unset (the installer exports it),
# so 'unset CDPATH' is defence in depth. Kept as a pass-expectation so a future relative cd that relies on it is noticed.
expect pass "R29 (equivalent) dropping 'unset CDPATH' leaves the verdict unchanged" gate_in "$D"
D=$(fresh_tree r30); mutate "$D" "$D/$I6" 'out_dir="$od_c"\n' '' || rc=1
expect fail "R30 the writers get the raw out-dir string instead of the checked canonical path" gate_in "$D"
D=$(fresh_tree r31); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'case "$out_dir" in /*) ;; *) out_dir="./$out_dir" ;; esac' 'true' || rc=1
expect fail "R31 the generator hands an option-like relative out-dir (--) to its tools" gate_in "$D"
D=$(fresh_tree r32); mutate "$D" "$D/$I6" '*) _prd="./$project_root" ;;' '*) _prd="$project_root" ;;' || rc=1
expect fail "R32 a relative --project-root '-' is entered bare (= OLDPWD)" gate_in "$D"
D=$(fresh_tree r33); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'sha256_stdin() { (builtin cd / && sha256sum) |' 'sha256_stdin() { sha256sum |' || rc=1
expect fail "R33 the generator hashes with sha256sum in a cwd holding a directory named '-' (uutils: empty hash)" gate_in "$D"
# review round 7 (R7-1..R7-5): the reviewer's mutants X1-X4, X6 and one mutant per byte-exact capture
G7="scripts/multitrack/gen_agent_label_defs.sh"
D=$(fresh_tree x1); mutate "$D" "$D/$I6" '    [ "${#t}" -lt "$pmax" ] || return 1' '    [ "${#t}" -le "$pmax" ] || return 1' || rc=1
expect fail "X1 canon() accepts a candidate of exactly PATH_MAX bytes (R7-3)" gate_in "$D"
D=$(fresh_tree x2); mutate "$D" "$D/$I6" '    [ "${#comp}" -le "$nmax" ] || return 1' '    [ "${#comp}" -lt "$nmax" ] || return 1' || rc=1
expect fail "X2 canon() refuses a legal NAME_MAX-byte component (R7-3)" gate_in "$D"
D=$(fresh_tree x3); mutate "$D" "$D/$I6" '    elif [ -d "$cur" ] && [ ! -x "$cur" ]; then' '    elif [ -d "$cur" ] && [ ! -r "$cur" ]; then' || rc=1
expect fail "X3 canon() tests read instead of search permission for EACCES (R7-3)" gate_in "$D"
D=$(fresh_tree x4); mutate "$D" "$D/$I6" 'local rest comp t l cur=/ n=0 base pmax nmax LC_ALL=C' 'local rest comp t l cur=/ n=0 base pmax nmax' || rc=1
expect fail "X4 canon() counts characters, not bytes (LC_ALL=C dropped, R7-3)" gate_in "$D"
D=$(fresh_tree x6); mutate "$D" "$D/$G7" '  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] ||' '  true ||' || rc=1
expect fail "X6 render() writes a file whose sha256 failed (R7-5)" gate_in "$D"
D=$(fresh_tree s1); mutate "$D" "$D/$I6" '  _eo_r="$("$@"; _eo_s=$?; printf x; exit "$_eo_s")" || _eo_s=$?' '  _eo_r="$("$@")x" || _eo_s=$?' || rc=1
expect fail "S1 exact_out() captures without the sentinel (trailing newlines stripped, R7-1)" gate_in "$D"
D=$(fresh_tree s2); mutate "$D" "$D/$I6" "  case \"\$EXACT\" in *\$'\\\\n'*) return 97 ;; esac\n" '' || rc=1
expect fail "S2 exact_out() accepts a captured path holding a newline (R7-1)" gate_in "$D"
D=$(fresh_tree s3); mutate "$D" "$D/$I6" '      exact_out command readlink -- "$t" 2>/dev/null || return 1' '      EXACT="$(command readlink -- "$t" 2>/dev/null)" || return 1' || rc=1
expect fail "S3 canon() captures a link target with a plain \$(...) (R7-1)" gate_in "$D"
D=$(fresh_tree s4); mutate "$D" "$D/$I6" '    *) exact_out builtin pwd -P 2>/dev/null || return 1; base="$EXACT";' '    *) base="$(builtin pwd -P 2>/dev/null)" || return 1;' || rc=1
expect fail "S4 canon() captures the cwd with a plain \$(...) (R7-2)" gate_in "$D"
D=$(fresh_tree s5); mutate "$D" "$D/$I6" '      [ "$ks" -ne 97 ] || return 1' '      true' || rc=1
expect fail "S5 canon_kcheck() accepts a kernel answer holding a newline (R7-1)" gate_in "$D"
D=$(fresh_tree s6); mutate "$D" "$D/$I6" '  exact_out canon "$2" || _crc=$?; _cv="$EXACT"' '  _cv="$(canon "$2")" || _crc=$?' || rc=1
expect fail "S6 canon_to() captures canon's output with a plain \$(...) (R7-1)" gate_in "$D"
D=$(fresh_tree s7); mutate "$D" "$D/$I6" 'if exact_out cdpwd "$_prd" && [ -n "$EXACT" ]; then project_root="$EXACT";' 'if EXACT="$(cdpwd "$_prd")" && [ -n "$EXACT" ]; then project_root="$EXACT";' || rc=1
expect fail "S7 the project root is captured with a plain \$(...) (R7-2)" gate_in "$D"
D=$(fresh_tree s8); mutate "$D" "$D/$G7" '  case "$f" in /*) ;; *) f="./$f" ;; esac\n' '' || rc=1
expect fail "S8 --classify hands an option-like relative name to sed/awk (R7-4)" gate_in "$D"
D=$(fresh_tree s9); mutate "$D" "$D/$I6" 'if ! exact_out cdpwd "$_srcd" || [ -z "$EXACT" ]; then' 'if ! EXACT="$(cdpwd "$_srcd")" || [ -z "$EXACT" ]; then' || rc=1
expect fail "S9 the installer's own directory is captured with a plain \$(...) (R7)" gate_in "$D"
D=$(fresh_tree s10); mutate "$D" "$D/$G7" 'if ! exact_out cdpwd "$_srcd" || [ -z "$EXACT" ]; then' 'if ! EXACT="$(cdpwd "$_srcd")" || [ -z "$EXACT" ]; then' || rc=1
expect fail "S10 the generator's own directory is captured with a plain \$(...) (R7)" gate_in "$D"
D=$(fresh_tree s11); mutate "$D" "$D/$I6" '  else exact_out builtin pwd -P 2>/dev/null; _r=$?' '  else EXACT="$(builtin pwd -P)"; _r=0' || rc=1
expect fail "S11 the default project root (cwd) is captured with a plain \$(...) (R7-2)" gate_in "$D"
D=$(fresh_tree ma); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" ' /snap /tmp /Users)' ' /snap /Users)' || rc=1
expect fail "MA /tmp dropped from SYS_EXACT (R4-2)" gate_in "$D"
D=$(fresh_tree mb); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" ' /sbin /srv /sys /usr)' ' /sbin /sys /usr)' || rc=1
mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'SYS_EXACT=(/var ' 'SYS_EXACT=(/srv /var ' || rc=1
expect fail "MB /srv moved from SYS_STRICT to SYS_EXACT (R4-3)" gate_in "$D"
D=$(fresh_tree me); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'case "$1" in "$2"/*) return 0' 'case "$1" in "$2"*) return 0' || rc=1
expect fail "ME under() matches a prefix without the slash (R4-4, over-refusal of /usrx, ~/.claudeless)" gate_in "$D"
D=$(fresh_tree r13); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ -n "$pw_home" ] && { add_uniq HOMES "$pw_home"; canon_to _cz "$pw_home"; add_uniq HOMES "$_cz"; }' 'true' || rc=1
expect fail "R13 installer ignores the passwd home when HOME is empty" gate_in "$D"

D=$(fresh_tree e2); expect pass "E2 ambient AGENT_TYPE_LABEL_AGENTS_DIR does not change the verdict" env AGENT_TYPE_LABEL_AGENTS_DIR=/tmp bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet

D=$(fresh_tree e1); expect pass "E1 ambient HP pointing elsewhere does not change the verdict" env HP="$T/nonexistent-hp" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet

D=$(fresh_tree m13); rm "$D/docs/scripts/gen_agent_label_defs.md"
expect fail "M13 missing generator doc" gate_in "$D"
D=$(fresh_tree m14); rm "$D/scripts/multitrack/install_agent_label_defs.sh"
expect fail "M14 missing installer" gate_in "$D"

# dispatch-log audit (gate-level)
D=$(fresh_tree m0b)
mkdir -p "$T/aud/agents"; bash "$D/scripts/multitrack/gen_agent_label_defs.sh" --track 1 --branch main --out-dir "$T/aud/agents" >/dev/null
printf '%s\n' '{"subagent_type":"general-purpose","description":"(T1/main - claude1 - opus - high) ATM-1 x"}' '{"subagent_type":"Explore","description":"(T1/main - claude1 - sonnet - low) y"}' >"$T/aud/bad.jsonl"
printf '%s\n' '{"subagent_type":"T1-main-sonnet-low","description":"(T1/main - claude1 - sonnet - low) y"}' '{"subagent_type":"plugin-dev:agent-creator","description":"(T1/main - claude1 - sonnet - low) z"}' '{"subagent_type":"general-purpose","description":"(T9/other - claude1 - sonnet - low) no types for T9"}' >"$T/aud/good.jsonl"
expect pass "A1 dispatch-log with a general-purpose dispatch, warn mode -> WARN only" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents"
expect fail "A2 same log, enforce mode -> FAIL" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" --mode enforce
expect pass "A3 golden-FALSE log (labelled types, specialists, track without types), enforce -> PASS" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/good.jsonl" --agents-dir "$T/aud/agents" --mode enforce
grep -q 'WARN' <(bash "$D/scripts/gates/cm_agent_type_label.sh" --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" 2>&1) && note "OK    A1b warn mode prints a WARN line" || { note "META FAIL: A1b warn mode prints a WARN line"; rc=1; }
expect fail "A4 unknown mode -> bad arg (nonzero)" bash "$D/scripts/gates/cm_agent_type_label.sh" --mode bogus
echo "----------------------------------------------------------------------"
[ "$rc" -eq 0 ] && { echo "META: PASS — CM-AGENT-TYPE-LABEL is not a bluff gate"; exit 0; } || { echo "META: FAIL — see above"; exit 1; }
