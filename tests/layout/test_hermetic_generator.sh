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

lint() { # TESTS_DIR -> prints offending files, one per line
  python3 -I - "$1" <<'PY'
import os, re, sys
direct = re.compile(r'^[^#\n]*\bbash\b[^\n|;&]*generate_agent_prefix_commands\.sh', re.M)
bad = []
for d, _, fs in os.walk(sys.argv[1]):
    for f in sorted(fs):
        if not f.endswith(".sh"):
            continue
        p = os.path.join(d, f); s = open(p, errors="replace").read()
        if not direct.search(s):
            continue
        if "HELIX_ACTION_OUT_ROOT" in s or re.search(r'\bcp\b[^\n]*generate_agent_prefix_commands', s):
            continue
        bad.append(os.path.relpath(p, sys.argv[1]))
print("\n".join(bad))
PY
}
tree_sum() { ( cd "$1" && { git ls-files -z -- plugins/helix/commands actions/generated 2>/dev/null | xargs -0 -r sha256sum; git status --porcelain -- plugins/helix/commands actions/generated 2>/dev/null; } | sha256sum | cut -c1-64 ); }

# (1) lint on the real tests, then on a mutated copy
out="$(lint "$SRC/tests")"
if [ -z "$out" ]; then lt_ok "lint: every direct generator invocation in tests/ is hermetic"; else lt_bad "lint: non-hermetic tests: $out"; fi
n_inst="$(grep -rl 'install_action_prefix' "$SRC/tests" --include='*.sh' 2>/dev/null | wc -l)"
lt_ok "lint info: $n_inst test files run the installer (covered by H3 copies, not by this lint)"
mkdir -p "$TB/lt/tests"; printf '#!/bin/bash\nbash "$REPO/scripts/generate_agent_prefix_commands.sh"\n' >"$TB/lt/tests/t.sh"
if [ "$(lint "$TB/lt/tests")" = "t.sh" ]; then lt_ok "lint mutant: a test without HELIX_ACTION_OUT_ROOT is flagged"; else lt_bad "lint mutant SURVIVED"; fi
printf '#!/bin/bash\nHELIX_ACTION_OUT_ROOT="$X" bash "$REPO/scripts/generate_agent_prefix_commands.sh"\n' >"$TB/lt/tests/t.sh"
if [ -z "$(lint "$TB/lt/tests")" ]; then lt_ok "lint golden-FALSE: a hermetic test is not flagged"; else lt_bad "lint false positive"; fi

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
