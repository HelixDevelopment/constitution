#!/usr/bin/env bash
# tests/layout/test_hermetic_generator.sh -- WIT-C02 (ownership redesign, defect P8): tests must not rewrite the
# REAL tracked generated command sets. Two checks, both with paired self-mutations (11.4.224, 1.1):
#  (1) LINT: every test that runs scripts/generate_agent_prefix_commands.sh directly either sets
#      HELIX_ACTION_OUT_ROOT or runs a private copy of the generator. (Installer tests cannot use the variable: the
#      installer deliberately unsets it and regenerates against its own const_root -- layout test H3 -- so those tests
#      must use a throw-away constitution copy; this lint reports them as a count, it does not pretend to cover them.)
#  (2) GUARD: with HELIX_ACTION_OUT_ROOT=<sandbox> the REAL generator writes only into the sandbox: the tracked
#      generated sets in the repo under test are byte-identical before and after, and the sandbox is complete.
# Mutations: a test that omits the variable -> lint FAILs; a generator that ignores the variable -> guard FAILs.
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
if [ -z "$bad" ]; then lt_ok "lint: no test runs the generator without a redirect, or an installer, from the real tree"; else lt_bad "lint: non-hermetic tests: $bad"; fi
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
ctrl_bad flagged
ctrl_good clean
EOF
)"
got="$(fx_expect "$LINT" | LC_ALL=C sort)"
lt_eq "lint fixtures: 6 reviewer violators + 6 more flagged, 7 golden-FALSE carriers clean, 1 exemption seen" "$(printf '%s\n' "$WANT" | LC_ALL=C sort)" "$got"

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
