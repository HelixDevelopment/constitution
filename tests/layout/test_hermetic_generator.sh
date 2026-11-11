#!/usr/bin/env bash
# tests/layout/test_hermetic_generator.sh -- WIT-C02 (ownership redesign, defect P8): tests must not rewrite the
# REAL tracked generated command sets. Two checks, both with paired self-mutations (11.4.224, 1.1):
#  (1) LINT (ADVISORY since review round 3 N5; decision recorded in CON-109 and the design doc): a static tripwire
#      that reports tests running scripts/generate_agent_prefix_commands.sh without HELIX_ACTION_OUT_ROOT, or an
#      installer, from the real tree. Findings on the real tests are printed as ADVISORY lines and do NOT fail this
#      suite: what a shell script executes is not decidable statically (the round-3 review measured 8 of 15 new
#      violator shapes missed), so the BINDING C02 check is the full-suite runner's per-unit fingerprint of the
#      generated sets plus its end-of-run tree identity (scripts/full_suite/run_full_suite.py gen_fingerprint /
#      quick_ident, pinned by tests/test_run_full_suite.sh section 39 and its mutants I1 I2 I3 G1). No new shapes are
#      added to the lint per review round (section 11.4.250). The lint's own documented behaviour stays checked on
#      its fixtures (1b) and by its paired mutations (1c), so it cannot rot silently.
#  (2) GUARD: with HELIX_ACTION_OUT_ROOT=<sandbox> the REAL generator writes only into the sandbox: the tracked
#      generated sets in the repo under test are byte-identical before and after, and the sandbox is complete.
# Mutations: a lint rule removed -> a fixture verdict changes (1c); a generator that ignores the variable -> guard FAILs.
# Env: LAYOUT_SRC_ROOT (tree under test). Exit 0 iff all pass.
LT_SUITE="hermetic_generator"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"
SRC="$LAYOUT_SRC_ROOT"; TB="$LT_SB"
lt_eq() { if [ "$2" = "$3" ]; then lt_ok "$1"; else lt_bad "$1 (expected [$2] got [$3])"; fi; }

tree_sum() { ( cd "$1" && { git ls-files -z -- plugins/helix/commands actions/generated 2>/dev/null | xargs -0 -r sha256sum; git status --porcelain -- plugins/helix/commands actions/generated 2>/dev/null; } | sha256sum | cut -c1-64 ); }
LINT="$SRC/tests/layout/hermetic_lint.py"
lint() { python3 -I "$1" "$2"; } # LINT_SCRIPT TESTS_DIR -> findings, one per line
# Exemptions (`# C02-hermetic: <reason>` on a line) the real tests are allowed to carry; any other is a FAIL.
EXPECTED_EXEMPT=""

# (1) lint on the real tests
out="$(lint "$LINT" "$SRC/tests")"
bad="$(printf '%s\n' "$out" | grep -v '^EXEMPT ' | grep -v '^$')"
ex="$(printf '%s\n' "$out" | grep '^EXEMPT ' | sed 's/^EXEMPT \([^ ]*\) .*/\1/')"
# ADVISORY (N5): findings are reported, never a FAIL here; the binding check is the runner's fingerprint
if [ -z "$bad" ]; then
  printf 'ADVISORY lint: 0 findings on the real tests\n'
else
  printf 'ADVISORY lint: %d finding(s) on the real tests (not a FAIL; the full-suite fingerprint is binding):\n' "$(printf '%s\n' "$bad" | grep -c .)"
  printf '%s\n' "$bad" | sed 's/^/ADVISORY   /'
fi
lt_ok "lint ran over the real tests (advisory result printed above)"
lt_eq "lint: the exemptions are exactly the expected list" "$EXPECTED_EXEMPT" "$ex"

# (1b) lint fixtures: the reviewer's six violators (wave 2 review, F5) and two controls, plus installer cases.
fx() { local n="$1"; shift; mkdir -p "$TB/fx/$n"; { echo '#!/bin/bash'; printf '%s\n' "$@"; } >"$TB/fx/$n/t.sh"; } # name line...
fx ctrl_bad 'bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx ctrl_good 'HELIX_ACTION_OUT_ROOT="$X" bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R1_env_unset 'env -u HELIX_ACTION_OUT_ROOT bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R2_comment_carrier '# note: HELIX_ACTION_OUT_ROOT is not needed here' 'bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R3_sh_not_bash 'sh "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R4_exec_path '"$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R5_continuation 'bash \' '  "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R6_var_holds_path 'G="$REPO/scripts/generate_agent_prefix_commands.sh"; bash "$G"'
fx R7_empty_redirect 'HELIX_ACTION_OUT_ROOT= bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R8_if_keyword 'if bash "$REPO/scripts/install_action_prefix.sh" "$P"; then :; fi'
fx R9_real_root_var 'here="$(cd "$(dirname "$0")/.." && pwd)"' 'inst(){ RC=0; HOME="$sb/home" bash "$here/scripts/install_cli_agent_plugins.sh" "$1" || RC=$?; }'
fx R10_for_var_real 'for r in "$LAYOUT_SRC_ROOT"; do bash "$r/scripts/install_cli_agent_plugins.sh"; done'
fx G1_copy_installer 'C="$(mktemp -d)"; cp -a "$REPO/scripts" "$C/"; bash "$C/scripts/install_action_prefix.sh" "$P"'
fx G2_relative_copy 'for rel in a b; do ( cd "$P" && bash "$rel/scripts/install_cli_agent_plugins.sh" ); done'
fx G3_printf_carrier 'printf "%s\n" "bash $REPO/scripts/generate_agent_prefix_commands.sh" > "$T/x.sh"'
fx G4_heredoc_carrier 'cat <<EOF' 'bash "$REPO/scripts/generate_agent_prefix_commands.sh"' 'EOF'
fx G5_env_redirect 'env HELIX_ACTION_OUT_ROOT="$W" bash "$W/../scripts/generate_agent_prefix_commands.sh"'
fx R11_quoted_heredoc_marker 'echo "a <<EOF"' 'bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx R12_installer_with_redirect 'HELIX_ACTION_OUT_ROOT="$X" bash "$REPO/scripts/install_action_prefix.sh" "$P"'
fx G6_continued_redirect 'HELIX_ACTION_OUT_ROOT="$X" \' '  bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx E1_exempt 'bash "$REPO/scripts/install_action_prefix.sh" "$P" # C02-hermetic: fixture reason'
# review round 2 R4: the reviewer's violators the round-2 lint missed (attacks/lint/t/v01..v14 of that review)
fx V01_nice_n 'nice -n 10 bash "$REPO/scripts/install_action_prefix.sh" --yes'
fx V02_timeout_s 'timeout -s KILL 60 bash "$REPO/scripts/install_cli_agent_plugins.sh"'
fx V03_source 'source "$REPO/scripts/install_action_prefix.sh"'
fx V04_dot '. "$REPO/scripts/install_action_prefix.sh"'
fx V05_dollar_bash '"$BASH" "$REPO/scripts/install_action_prefix.sh"'
fx V06_bash_o 'bash -o pipefail "$REPO/scripts/install_action_prefix.sh"'
fx V07_func 'run() { "$@"; }' 'run bash "$REPO/scripts/install_action_prefix.sh"'
fx V07b_func_multiline 'run() {' '  echo running' '  "$@"' '}' 'run bash "$REPO/scripts/install_action_prefix.sh"'
fx V09_name_var 'N=install_action_prefix.sh' 'bash "$REPO/scripts/$N"'
fx V10_gen_nice 'nice -n 5 bash "$REPO/scripts/generate_agent_prefix_commands.sh"'
fx V14_xargs 'echo "$REPO/scripts/install_action_prefix.sh" | xargs bash'
fx V15_bash_c 'bash -c "bash $REPO/scripts/install_action_prefix.sh"'
# golden-FALSE carriers of the round-3 rules (nothing here runs a target from the real tree)
fx G7_source_lib 'source "$REPO/tests/extensions/lib.sh"'
fx G8_nice_copy 'C="$(mktemp -d)"; cp -a "$REPO/scripts" "$C/"; nice -n 10 bash "$C/scripts/install_action_prefix.sh"'
fx G9_echo_no_xargs 'echo "$REPO/scripts/install_action_prefix.sh" > "$T/list"'
fx G10_func_not_wrapper 'run() { echo "$@"; }' 'run bash "$REPO/scripts/install_action_prefix.sh"'
# G11: the echo and the xargs are joined by ";" not "|", so xargs never reads that path (it reads the test's stdin)
fx G11_xargs_not_piped 'echo "$REPO/scripts/install_action_prefix.sh"; xargs -r bash'
fx G12_name_var_other 'N=other_script.sh' 'bash "$REPO/scripts/$N"'
fx_expect() { # LINT_SCRIPT -> one line per fixture: name flagged|clean|exempt
  local d r
  for d in "$TB"/fx/*/; do
    r="$(lint "$1" "$d")"
    case "$r" in EXEMPT*) echo "$(basename "$d") exempt";; "") echo "$(basename "$d") clean";; *) echo "$(basename "$d") flagged";; esac
  done
}
WANT="$(cat <<'EOF'
E1_exempt exempt
G1_copy_installer clean
G2_relative_copy clean
G3_printf_carrier clean
G4_heredoc_carrier clean
G5_env_redirect clean
G6_continued_redirect clean
G7_source_lib clean
G8_nice_copy clean
G9_echo_no_xargs clean
G10_func_not_wrapper clean
G11_xargs_not_piped clean
G12_name_var_other clean
R10_for_var_real flagged
R11_quoted_heredoc_marker flagged
R12_installer_with_redirect flagged
R1_env_unset flagged
R2_comment_carrier flagged
R3_sh_not_bash flagged
R4_exec_path flagged
R5_continuation flagged
R6_var_holds_path flagged
R7_empty_redirect flagged
R8_if_keyword flagged
R9_real_root_var flagged
V01_nice_n flagged
V02_timeout_s flagged
V03_source flagged
V04_dot flagged
V05_dollar_bash flagged
V06_bash_o flagged
V07_func flagged
V07b_func_multiline flagged
V09_name_var flagged
V10_gen_nice flagged
V14_xargs flagged
V15_bash_c flagged
ctrl_bad flagged
ctrl_good clean
EOF
)"
got="$(fx_expect "$LINT" | LC_ALL=C sort)"
lt_eq "lint fixtures: 6+12 reviewer violators + 6 more flagged, 13 golden-FALSE carriers clean, 1 exemption seen" "$(printf '%s\n' "$WANT" | LC_ALL=C sort)" "$got"

# (1c) paired mutations of the lint itself: each RULE removed must change at least one fixture verdict
lint_mut() { # id old new
  local m="$TB/lm_$1.py"
  python3 -I - "$LINT" "$m" "$2" "$3" <<'PY2'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert s.count(old) == 1, (old, s.count(old))
open(dst, "w").write(s.replace(old, new))
PY2
  [ "$(fx_expect "$m" | LC_ALL=C sort)" != "$(printf '%s\n' "$WANT" | LC_ALL=C sort)" ] && lt_ok "lint mutant $1 killed" || lt_bad "lint mutant $1 SURVIVED"
}
lint_mut L1_no_continuation 'if raw.endswith("\\") and not raw.lstrip().startswith("#"):' 'if False:'
lint_mut L2_unassigned_not_real 'return v in real or (v not in assigned and v not in raw)' 'return v in real'
lint_mut L3_no_held_var 'if v in held and word in' 'if False and word in'
lint_mut L4_empty_redirect_ok 'env.get("HELIX_ACTION_OUT_ROOT", "") != ""' '"HELIX_ACTION_OUT_ROOT" in env'
lint_mut L5_no_keywords 'if w in KEYWORDS:' 'if False:'
lint_mut L6_no_for_var 'if len(c) >= 2 and c[0] == "for":' 'if False:'
lint_mut L7_no_raw_assign 'raw.setdefault(name, []).append(val)' 'pass'
lint_mut L8_unset_redirects 'env.pop(c[i + 1], None)' 'env[c[i + 1]] = "x"'
lint_mut L9_no_heredoc_skip '            term = m.group(2)' '            term = None'
lint_mut L11_heredoc_in_quotes 'QUOTED.sub("", buf)' 'buf'
lint_mut L10_installers_redirectable 'if target == GEN and env.get' 'if env.get'
# round 3 (review round 2 R4) rules
lint_mut L12_no_wrapper_opt_value 'if c[i] in vopts:  # RULE:C02-lint-wrapper-opt-value' 'if False:'
lint_mut L13_no_source_or_shell_vars 'if os.path.basename(word) in SHELLS or word in SHELL_VARS or word in SOURCERS:' 'if os.path.basename(word) in SHELLS:'
lint_mut L14_no_shell_opt_value 'j += 2 if c[j] in SHELL_VALUE_OPTS else 1' 'j += 1'
lint_mut L15_no_func_wrapper 'if w in WRAPPERS or w in funcs:' 'if w in WRAPPERS:'
lint_mut L16_no_tail_var 'paths = [x for p_ in paths for x in expand_tail(p_)]' 'pass'
lint_mut L17_no_xargs_stdin 'stdin_paths = [x for x in prev[1:] if not x.startswith("-")]' 'pass'
lint_mut L18_no_dash_c 'if c[j] == "-c" and j + 1 < len(c):  # RULE:C02-lint-dash-c' 'if False:'
lint_mut L19_xargs_any_sep 'if w == "xargs" and sep == "|" and prev' 'if w == "xargs" and prev'
lint_mut L20_func_any_body 'if fm and line.rstrip().endswith("}") and RUNS_ARGS.search(fm.group(2).strip()):' 'if fm and line.rstrip().endswith("}"):'

# (2) guard on the real generator
gd() { # generator_script sandbox_root -> runs it redirected
  HELIX_ACTION_OUT_ROOT="$2" HELIX_GEN_LOCK_WAIT=60 bash "$1" >/dev/null 2>&1
}
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  before="$(tree_sum "$SRC")"; mkdir -p "$TB/g1/plugins/helix"
  gd "$SRC/scripts/generate_agent_prefix_commands.sh" "$TB/g1"; rc=$?
  after="$(tree_sum "$SRC")"
  lt_eq "guard: generator rc 0 with a redirected root" 0 "$rc"
  lt_eq "guard: the tracked generated sets are byte-identical" "$before" "$after"
  [ "${#before}" -eq 64 ] && lt_ok "guard: the checksum was really computed (64 hex)" || lt_bad "guard: empty checksum [$before]"
  lt_eq "guard: sandbox got the Claude plugin command set" "$(ls "$SRC"/plugins/helix/commands/*.md | wc -l)" "$(ls "$TB"/g1/plugins/helix/commands/*.md 2>/dev/null | wc -l)"
  # mutant: a generator that ignores the redirect rewrites the tracked tree's location -> the sandbox stays empty
  mkdir -p "$TB/mut/scripts" "$TB/mut/actions"; cp -a "$SRC/scripts/." "$TB/mut/scripts/"; cp -a "$SRC/actions/registry.yaml" "$TB/mut/actions/"
  mkdir -p "$TB/mut/plugins/helix"
  python3 -I - "$TB/mut/scripts/generate_agent_prefix_commands.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); a = 'gen_root="${HELIX_ACTION_OUT_ROOT:-$const_root}"'
assert s.count(a) == 1; open(p, "w").write(s.replace(a, 'gen_root="$const_root"'))
PY
  mkdir -p "$TB/g2/plugins/helix"; gd "$TB/mut/scripts/generate_agent_prefix_commands.sh" "$TB/g2"
  if [ "$(ls "$TB"/g2/plugins/helix/commands/*.md 2>/dev/null | wc -l)" -eq 0 ]; then lt_ok "guard mutant: a generator ignoring the redirect leaves the sandbox empty (detected)"; else lt_bad "guard mutant SURVIVED"; fi
else
  lt_ok "guard skipped: tree under test is not a git checkout (SKIP, no tracked sets to compare)"
fi
lt_summary
