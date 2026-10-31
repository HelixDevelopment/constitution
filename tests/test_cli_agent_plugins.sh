#!/usr/bin/env bash
# tests/test_cli_agent_plugins.sh — hermetic test suite for the CLI-agent
# plugin / skill wiring (§11.4.140 action directives + §11.4.164 auto-load seam).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Exercise the REAL scripts (never a re-implementation of them) against REAL
# artefacts inside a disposable sandbox, and assert the behaviours the gate
# CM-CLI-AGENT-PLUGINS-WIRED can only assert statically:
#
#   C1  GENERATION      — a synthetic action in a temp registry produces the
#                         Claude command pair + gemini/qwen TOML + codex MD.
#                         (Also probes whether HELIX_ACTION_REGISTRY redirects
#                         the OUTPUT path — reported honestly, never worked around.)
#   C2  DETERMINISM     — generating twice is byte-identical (§11.4.50).
#   C3  COLLISION       — an action with `slash_conflicts` gets the CONFLICT note;
#       + NEGATIVE        an action WITHOUT one does NOT (a spurious conflict note
#                         would be a §11.4.201 FAIL-bluff), and the collision-free
#                         `default-` alias never carries it either.
#   C4  IDEMPOTENT      — install_cli_agent_plugins.sh --skills-only twice: every
#       INSTALL           skill lands in .claude/skills/<name> as a SYMLINK (BY
#                         REFERENCE, never a copy — §11.4.28/§11.4.80) pointing into
#                         the constitution, and the 2nd run changes nothing.
#   C5  POST-UPDATE     — post_update_hook.sh detects a changed skill and actually
#       DETECTS + WIRES   installs it + calls the installer. This is the permanent
#                         regression guard (§11.4.135) for the `cmd | while read`
#                         SUBSHELL bug that silently emptied the arrays.
#   C5b RED BASELINE    — the pre-fix pipeline form is REPRODUCED standalone and
#                         shown to lose the array (§11.4.115 RED), and the CURRENT
#                         hook is asserted NOT to use it (GREEN). Without C5b, C5
#                         could pass blindly.
#   C6  NO-FAKE-SUCCESS — with `claude` absent from PATH the installer prints the
#                         exact manual commands and NEVER claims the plugin is
#                         installed (§11.4.6).
#
# Self-validating (§11.4.107(10)): C3 carries a golden-good (conflict declared →
# note present) AND a golden-bad/negative control (no conflict → note absent), so
# an always-say-yes check cannot pass. C5 carries its RED baseline (C5b).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/test_cli_agent_plugins.sh [--quiet]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   The constitution tree this file lives in (READ-ONLY — copied into a sandbox).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case, a FINDINGS section, a summary.
#   Exit 0 — every case passed. Exit 1 — a case failed.
#   FINDINGS are defects/boundaries in scripts owned by another work stream: they
#   are REPORTED (never patched here) and do NOT alter this suite's exit code —
#   the summary states their count explicitly so they cannot be silently absorbed.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE outside `mktemp -d` (removed by the EXIT trap — §11.4.14). The real repo,
#   the real ~/.claude config and the operator's plugin install are never touched:
#   every script under test runs against a sandbox COPY, and the steps that could
#   reach the real Claude Code config run with `claude` removed from PATH and
#   CLAUDE_CONFIG_DIR pointed at the sandbox.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, git, python3 (+PyYAML), sha256sum, mktemp, sed, grep, find.
#   Parses clean under bash -n and sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 · §11.4.164 · §11.4.50 (determinism) · §11.4.115 (RED baseline) ·
#   §11.4.135 (permanent regression guard) · §11.4.201 (real conditions, no
#   proxy signals) · §11.4.6 (no-guessing — honest findings) ·
#   gate: scripts/gates/cm_cli_agent_plugins_wired.sh
#
# Classification: universal (§11.4.17)
# Last verified: 2026-07-15
set -u

SUITE="cli-agent-plugins"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/.." >/dev/null 2>&1 && pwd)
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

PASSES=0
FAILURES=0
FINDINGS=0
FINDING_TEXT=""

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { PASSES=$((PASSES + 1));   say "  PASS  [$SUITE] $*"; }
no()   { FAILURES=$((FAILURES + 1)); printf '  FAIL  [%s] %s\n' "$SUITE" "$*" >&2; }
note() {
	FINDINGS=$((FINDINGS + 1))
	FINDING_TEXT="${FINDING_TEXT}  F${FINDINGS}. $*
"
	printf '  FINDING [%s] %s\n' "$SUITE" "$*" >&2
}

TMP=$(mktemp -d) || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# A PATH with NO `claude` on it — so nothing in this suite can ever reach the
# operator's real plugin install. CLAUDE_CONFIG_DIR is also sandboxed.
SAFE_PATH="/usr/bin:/bin"
export CLAUDE_CONFIG_DIR="$TMP/claude-config"
mkdir -p "$CLAUDE_CONFIG_DIR"

# make_const <dest> — a sandbox COPY of everything the scripts under test read.
# Constitution.md is included because post_update_hook.sh fails closed unless the
# resolved CONST_DIR actually looks like the constitution root (its §11.4.6 guard).
make_const() {
	dest="$1"
	mkdir -p "$dest/scripts"
	cp -a "$ROOT/.claude-plugin" "$dest/.claude-plugin"
	cp -a "$ROOT/plugins"        "$dest/plugins"
	cp -a "$ROOT/actions"        "$dest/actions"
	cp -a "$ROOT/skills"         "$dest/skills"
	cp -a "$ROOT/Constitution.md" "$dest/Constitution.md"
	for s in action_prefix_lib.sh generate_agent_prefix_commands.sh \
	         install_cli_agent_plugins.sh post_update_hook.sh \
	         portable_symlink_lib.sh; do
		cp -a "$ROOT/scripts/$s" "$dest/scripts/$s"
	done
	# install_cli_agent_plugins.sh optionally sources lib/constitution_layout.sh
	mkdir -p "$dest/scripts/lib"
	cp -a "$ROOT/scripts/lib/constitution_layout.sh" "$dest/scripts/lib/constitution_layout.sh"
}

# hash_tree <dir> — stable sha256 manifest of every file under <dir>.
hash_tree() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null); }

say "== $SUITE hermetic suite (sandbox: $TMP) =="

# ─────────────────────────────────────────────────────────────────────────────
# Fixture: a synthetic registry with THREE test actions.
#   ZZTESTACTION — plain action (generation)
#   ZZCONFLICT   — declares slash_conflicts: [zzhost]  → CONFLICT note expected
#   ZZCLEAN      — declares slash_conflicts: []        → NO note expected (negative control)
# ─────────────────────────────────────────────────────────────────────────────
REG="$TMP/synthetic_registry.yaml"
cat > "$REG" <<'YAMLEOF'
schema_version: 1

grammar:
  prefix_regex: '^([A-Z][A-Z0-9_]*) :: '
  body_separator: ' :: '
  case_sensitive: true

actions:
  - name: ZZTESTACTION
    version: 1
    namespaces: [DEFAULT]
    slash_bare: auto
    slash_conflicts: []
    summary: >-
      Synthetic fixture action for the hermetic test suite.
    expansion: >-
      SYNTHETIC EXPANSION ZZTESTACTION — hermetic test fixture only.

  - name: ZZCONFLICT
    version: 1
    namespaces: [DEFAULT]
    slash_bare: auto
    slash_conflicts: [zzhost]
    summary: >-
      Synthetic fixture action that collides with a host built-in.
    expansion: >-
      SYNTHETIC EXPANSION ZZCONFLICT — hermetic test fixture only.

  - name: ZZCLEAN
    version: 1
    namespaces: [DEFAULT]
    slash_bare: auto
    slash_conflicts: []
    summary: >-
      Synthetic fixture action with NO host collision (negative control).
    expansion: >-
      SYNTHETIC EXPANSION ZZCLEAN — hermetic test fixture only.
YAMLEOF

# ── C1 — GENERATION from a temp registry ────────────────────────────────────
CGEN="$TMP/const_gen"
make_const "$CGEN"
gen_out="$TMP/gen1.log"
if ( cd "$CGEN" && HELIX_ACTION_REGISTRY="$REG" bash scripts/generate_agent_prefix_commands.sh ) >"$gen_out" 2>&1; then
	missing=""
	for f in \
		"$CGEN/plugins/helix/commands/zztestaction.md" \
		"$CGEN/plugins/helix/commands/default-zztestaction.md" \
		"$CGEN/actions/generated/gemini/zztestaction.toml" \
		"$CGEN/actions/generated/qwen/zztestaction.toml" \
		"$CGEN/actions/generated/codex/zztestaction.md" ; do
		[ -s "$f" ] || missing="$missing $(basename "$(dirname "$f")")/$(basename "$f")"
	done
	if [ -z "$missing" ]; then
		if grep -q 'SYNTHETIC EXPANSION ZZTESTACTION' "$CGEN/plugins/helix/commands/zztestaction.md"; then
			ok "C1 generation: HELIX_ACTION_REGISTRY honoured for INPUT — ZZTESTACTION produced the Claude pair + gemini/qwen TOML + codex MD, carrying its registry expansion"
		else
			no "C1 generation: zztestaction.md does not carry the registry expansion text"
		fi
	else
		no "C1 generation: missing generated file(s):$missing"
	fi
else
	no "C1 generation: generator FAILED (see $gen_out)"; sed 's/^/        | /' "$gen_out" >&2
fi

# C1b — does HELIX_ACTION_REGISTRY redirect the OUTPUT path too? (honest probe)
# The registry lives OUTSIDE the sandbox const tree; if outputs followed the
# registry, nothing would land under $CGEN. Report what is actually true.
if [ -s "$CGEN/plugins/helix/commands/zztestaction.md" ] && [ ! -e "$TMP/plugins" ]; then
	if ! grep -q 'HELIX_ACTION_OUT_ROOT' "$ROOT/scripts/generate_agent_prefix_commands.sh"; then
		note "generate_agent_prefix_commands.sh honours \$HELIX_ACTION_REGISTRY for INPUT only — output paths are ALWAYS derived from the generator's OWN location (const_root=\$script_dir/..). Consequence: pointing the REAL generator at a foreign registry REWRITES the real plugins/helix/commands + actions/generated + plugins/helix/README.md from that registry. Not a bug in itself, but a live foot-gun: there is no --out-dir. This suite therefore only ever runs a SANDBOX COPY of the generator (never the repo's own)."
	else
		ok "C1 out-root: the generator honours \$HELIX_ACTION_OUT_ROOT — input and output are independently steerable, so pointing it at a foreign registry cannot rewrite the real command tree"
	fi
fi

# C1c — the generator never PRUNES: the sandbox copy still carries the 10 real
# commands alongside the 6 synthetic ones. Stale commands can only be caught by
# the gate's set-diff (invariant 8), which is exactly why it regenerates into an
# EMPTY dir. Record as an honest boundary.
if [ -e "$CGEN/plugins/helix/commands/background.md" ]; then
	note "generate_agent_prefix_commands.sh does NOT prune: a command file for an action REMOVED from the registry is left behind (regenerating over an existing tree never deletes). The gate compensates (invariant 8 regenerates into an EMPTY dir and diffs the file SET), but the generator itself cannot self-heal a stale command."
fi

# ── C2 — DETERMINISM (§11.4.50) ─────────────────────────────────────────────
CDET="$TMP/const_det"
make_const "$CDET"
( cd "$CDET" && HELIX_ACTION_REGISTRY="$REG" bash scripts/generate_agent_prefix_commands.sh ) >/dev/null 2>&1
h1=$(hash_tree "$CDET/plugins/helix/commands"; hash_tree "$CDET/actions/generated")
( cd "$CDET" && HELIX_ACTION_REGISTRY="$REG" bash scripts/generate_agent_prefix_commands.sh ) >/dev/null 2>&1
h2=$(hash_tree "$CDET/plugins/helix/commands"; hash_tree "$CDET/actions/generated")
if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then
	ok "C2 determinism: two consecutive generations are byte-identical (sha256 manifest of every generated file)"
else
	no "C2 determinism: generation is NOT deterministic — the two runs differ"
	printf '%s\n' "$h1" > "$TMP/h1"; printf '%s\n' "$h2" > "$TMP/h2"
	diff "$TMP/h1" "$TMP/h2" | sed 's/^/        | /' >&2
fi

# ── C3 — COLLISION handling + NEGATIVE control ──────────────────────────────
conf_md="$CGEN/plugins/helix/commands/zzconflict.md"
clean_md="$CGEN/plugins/helix/commands/zzclean.md"
def_conf_md="$CGEN/plugins/helix/commands/default-zzconflict.md"
c3=0
if [ -s "$conf_md" ] && grep -q 'CONFLICT (registry `slash_conflicts`)' "$conf_md" && grep -q 'zzhost' "$conf_md"; then
	ok "C3 collision (golden-good): ZZCONFLICT declares slash_conflicts=[zzhost] → zzconflict.md carries the CONFLICT note naming the host command"
else
	no "C3 collision: zzconflict.md is missing the CONFLICT note (or does not name the colliding host command)"; c3=1
fi
if [ -s "$clean_md" ] && ! grep -q 'CONFLICT (registry' "$clean_md"; then
	ok "C3 collision (NEGATIVE control): ZZCLEAN declares no conflict → zzclean.md carries NO conflict note (no false-positive conflict)"
else
	no "C3 collision NEGATIVE control: zzclean.md carries a SPURIOUS conflict note — a false-positive conflict is a §11.4.201 FAIL-bluff"; c3=1
fi
if [ -s "$def_conf_md" ] && ! grep -q 'CONFLICT (registry' "$def_conf_md"; then
	ok "C3 collision (alias): the collision-free alias default-zzconflict.md carries no conflict note (it is the escape hatch, not the colliding form)"
else
	no "C3 collision: default-zzconflict.md unexpectedly carries a conflict note (the alias cannot collide)"; c3=1
fi
[ "$c3" -eq 0 ] || true

# ── C4 — IDEMPOTENT INSTALL (skills BY REFERENCE) ───────────────────────────
CINS="$TMP/const_inst"
make_const "$CINS"
PROJ="$TMP/proj_install"
mkdir -p "$PROJ"
run1="$TMP/install1.log"; run2="$TMP/install2.log"
PATH="$SAFE_PATH" bash "$CINS/scripts/install_cli_agent_plugins.sh" "$PROJ" --skills-only >"$run1" 2>&1 || true
snap1=$( (cd "$PROJ/.claude/skills" 2>/dev/null && find . -maxdepth 1 -mindepth 1 | LC_ALL=C sort | while IFS= read -r l; do printf '%s -> %s\n' "$l" "$(readlink "$l" 2>/dev/null)"; done) )
PATH="$SAFE_PATH" bash "$CINS/scripts/install_cli_agent_plugins.sh" "$PROJ" --skills-only >"$run2" 2>&1 || true
snap2=$( (cd "$PROJ/.claude/skills" 2>/dev/null && find . -maxdepth 1 -mindepth 1 | LC_ALL=C sort | while IFS= read -r l; do printf '%s -> %s\n' "$l" "$(readlink "$l" 2>/dev/null)"; done) )

n_links=0; bad_links=0
for d in "$CINS"/skills/*/; do
	[ -f "${d}SKILL.md" ] || continue
	sk=$(basename "$d")
	lnk="$PROJ/.claude/skills/$sk"
	n_links=$((n_links + 1))
	if [ ! -L "$lnk" ]; then
		no "C4 install: $lnk is NOT a symlink (skills MUST be inherited BY REFERENCE, never copied — §11.4.28/§11.4.80)"; bad_links=$((bad_links + 1)); continue
	fi
	tgt=$(readlink "$lnk")
	# The installer stores link-relative targets (§11.4.111); resolve against the
	# link's own directory before asserting the target is inside the constitution.
	case "$tgt" in /*) : ;; *) tgt=$(cd "$(dirname "$lnk")" && cd "$(dirname "$tgt")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$tgt")") ;; esac
	case "$tgt" in
		"$CINS"/skills/*) : ;;
		*) no "C4 install: $lnk points at '$tgt' — NOT into the constitution skills dir"; bad_links=$((bad_links + 1)) ;;
	esac
done
if [ "$n_links" -eq 0 ]; then
	no "C4 install: no SKILL.md skill was linked into .claude/skills/"
elif [ "$bad_links" -eq 0 ]; then
	ok "C4 install: all $n_links SKILL.md skill(s) linked into .claude/skills/ as SYMLINKS pointing into the constitution (by reference)"
fi
if [ -n "$snap1" ] && [ "$snap1" = "$snap2" ]; then
	ok "C4 install: IDEMPOTENT — the second run leaves .claude/skills/ byte-for-byte identical (same names, same targets)"
else
	no "C4 install: NOT idempotent — the second run changed .claude/skills/"
	printf '%s\n' "$snap1" | sed 's/^/        1| /' >&2
	printf '%s\n' "$snap2" | sed 's/^/        2| /' >&2
fi

# ── C6 — NO-FAKE-SUCCESS when the `claude` CLI is absent ────────────────────
# (Run here because it reuses the C4 sandbox; ordering is irrelevant.)
PROJ_NP="$TMP/proj_noclaude"
mkdir -p "$PROJ_NP"
np="$TMP/install_noclaude.log"
env -u PATH PATH="$SAFE_PATH" bash "$CINS/scripts/install_cli_agent_plugins.sh" "$PROJ_NP" >"$np" 2>&1 || true
if PATH="$SAFE_PATH" command -v claude >/dev/null 2>&1; then
	no "C6 no-fake-success: PRE-CONDITION broken — \`claude\` IS on the sandboxed PATH, so this case proves nothing"
else
	c6=0
	grep -q 'CLI is NOT on PATH' "$np" || { no "C6 no-fake-success: the installer did not report the missing \`claude\` CLI"; c6=1; }
	grep -q 'claude plugin marketplace add' "$np" || { no "C6 no-fake-success: the installer did not print the manual 'marketplace add' command"; c6=1; }
	grep -q 'claude plugin install' "$np"        || { no "C6 no-fake-success: the installer did not print the manual 'plugin install' command"; c6=1; }
	if grep -q 'is INSTALLED' "$np"; then
		no "C6 no-fake-success: the installer CLAIMED the plugin is installed while the \`claude\` CLI was absent — that is a §11.4.6 fake success"; c6=1
	fi
	[ "$c6" -eq 0 ] && ok "C6 no-fake-success: with \`claude\` off PATH the installer reports the absence + the exact manual commands, and NEVER claims the plugin is installed"
fi

# ── C5b — RED BASELINE: the pre-fix `cmd | while read` subshell array loss ──
# §11.4.115: prove the DEFECT is real and detectable before asserting the fix.
red_lost=0
red_kept=0
# The OLD form: the loop body runs in a SUBSHELL, so the array is empty afterwards.
OLD_ARR=()
printf 'one\ntwo\n' | while IFS= read -r l; do OLD_ARR+=("$l"); done
[ "${#OLD_ARR[@]}" -eq 0 ] && red_lost=1
# The CURRENT form (process substitution): the loop body runs in THIS shell.
NEW_ARR=()
while IFS= read -r l; do NEW_ARR+=("$l"); done < <(printf 'one\ntwo\n')
[ "${#NEW_ARR[@]}" -eq 2 ] && red_kept=1
if [ "$red_lost" -eq 1 ] && [ "$red_kept" -eq 1 ]; then
	ok "C5b RED baseline: reproduced the defect — \`printf | while read; do ARR+=() done\` leaves the array EMPTY (0 elems) while the process-substitution form keeps both elems (2). The bug class is real and detectable."
else
	no "C5b RED baseline: could NOT reproduce the subshell array loss (lost=$red_lost kept=$red_kept) — this shell does not exhibit the bug class, so C5's regression guard is blind here"
fi
# And the CURRENT hook must not use the losing form for its classification loop.
if grep -q 'for f in "${changed_files\[@\]}"' "$ROOT/scripts/post_update_hook.sh" && \
   ! grep -q '"\$changed_files" | while' "$ROOT/scripts/post_update_hook.sh"; then
	ok "C5b GREEN: post_update_hook.sh feeds its classification loop by process substitution (\`done < <(printf ...)\`), NOT by a pipe — the subshell bug cannot recur"
else
	no "C5b GREEN: post_update_hook.sh does NOT use process substitution for the classification loop — the subshell array-loss bug may be back"
fi

# ── C5 — POST-UPDATE HOOK detects a changed skill and wires it ──────────────
# Mirrors reality: the constitution is its OWN git repo (a submodule), the
# consuming project is a separate repo.
CREPO="$TMP/const_repo"
make_const "$CREPO"
PROJ2="$TMP/proj_hook"
mkdir -p "$PROJ2"
(
	cd "$CREPO" && \
	git init -q . && \
	git -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1 && \
	git -c user.email=t@t -c user.name=t commit -q -m "base" >/dev/null 2>&1
) || no "C5 setup: could not create the sandbox constitution git repo"
( cd "$PROJ2" && git init -q . ) || no "C5 setup: could not create the sandbox project git repo"

# The change under test: a skill file is modified in the new constitution commit.
printf '\n<!-- hermetic-test touch -->\n' >> "$CREPO/skills/action-prefix-system/SKILL.md"
(
	cd "$CREPO" && \
	git -c user.email=t@t -c user.name=t commit -q -am "modify a skill" >/dev/null 2>&1
) || no "C5 setup: could not create the second commit"

hook_log="$TMP/post_update.log"
PATH="$SAFE_PATH" CONST_DIR="$CREPO" PROJECT_ROOT="$PROJ2" \
	bash "$CREPO/scripts/post_update_hook.sh" >"$hook_log" 2>&1 || true

c5=0
if grep -qE 'Detected: [1-9][0-9]* skill\(s\)' "$hook_log"; then
	: # non-zero changed-skill count — the arrays survived the classification loop
else
	no "C5 post-update: the hook reported ZERO changed skills for a commit that modified a skill — the classification arrays are empty (the subshell bug, or a detection regression)"
	c5=1
fi
grep -q 'Installing skill: action-prefix-system' "$hook_log" || { no "C5 post-update: the hook did not install the changed skill"; c5=1; }
[ -L "$PROJ2/skills/action-prefix-system" ] || { no "C5 post-update: the hook did not link the skill into <project>/skills/"; c5=1; }
grep -q 'STEP 4b' "$hook_log" || { no "C5 post-update: STEP 4b (action-plugin wiring) never ran"; c5=1; }
grep -q 'install_cli_agent_plugins.sh' "$hook_log" || { no "C5 post-update: the hook never invoked install_cli_agent_plugins.sh"; c5=1; }
[ -L "$PROJ2/.claude/skills/action-prefix-system" ] || { no "C5 post-update: the installer did not link the skill into <project>/.claude/skills/ (the native discovery path)"; c5=1; }
if [ "$c5" -eq 0 ]; then
	ok "C5 post-update: a changed skill is DETECTED (non-zero count), installed, and the §11.4.164 seam runs install_cli_agent_plugins.sh, which links it into .claude/skills/ — the subshell-bug regression guard is GREEN"
else
	sed 's/^/        | /' "$hook_log" >&2
fi

# C5c — DEFAULT CONST_DIR: the hook must work with NO env at all.
# PERMANENT REGRESSION GUARD (§11.4.135) for a defect this suite reproduced and
# the owner then fixed: the default used to be `$SCRIPT_DIR/../..`, which lands on
# the PARENT project root, so `git diff` ran against the parent repo (whose paths
# look like "constitution/skills/...") and matched NONE of the classifiers — the
# hook reported "Detected: 0 skill(s) ... Nothing to propagate" and propagated
# NOTHING, silently. The default is now `$SCRIPT_DIR/..`. RED→GREEN per §11.4.115:
# this case FAILED before the fix and passes after it. It must never regress.
PROJ3="$TMP/proj_hook_default"
mkdir -p "$PROJ3"
( cd "$PROJ3" && git init -q . ) || no "C5c setup: could not init the sandbox project repo"
def_log="$TMP/post_update_default.log"
( cd "$PROJ3" && PATH="$SAFE_PATH" bash "$CREPO/scripts/post_update_hook.sh" ) >"$def_log" 2>&1 || true
c5c=0
grep -qE 'Detected: [1-9][0-9]* skill\(s\)' "$def_log" || { no "C5c default CONST_DIR: with NO env set, the hook detected ZERO changed skills — it is NOT resolving the constitution root from its own location (the '../..' off-by-one is back)"; c5c=1; }
[ -L "$PROJ3/.claude/skills/action-prefix-system" ] || { no "C5c default CONST_DIR: with NO env set, the hook did not wire the skill into <project>/.claude/skills/"; c5c=1; }
if [ "$c5c" -eq 0 ]; then
	ok "C5c default CONST_DIR: invoked with NO env at all, the hook resolves the constitution from its OWN location, detects the changed skill, and wires it (regression guard for the '../..' off-by-one)"
else
	sed 's/^/        | /' "$def_log" >&2
fi
# Static companion: the default expression itself must be one level up, not two.
if grep -q '_pu_self="\$(cd "\$SCRIPT_DIR/\.\." && pwd)"' "$ROOT/scripts/post_update_hook.sh" && \
   grep -q '^CONST_DIR="\$_pu_self"$' "$ROOT/scripts/post_update_hook.sh"; then
	ok "C5c static: CONST_DIR is always \`\$SCRIPT_DIR/..\` (the constitution root, never the parent project, never an ambient CONST_DIR)"
else
	no "C5c static: the CONST_DIR default is NOT \`\$SCRIPT_DIR/..\` — verify it still resolves to the constitution root"
fi
# C5d — data-safety probe on install_skills' destination handling.
# NB: strip comment lines FIRST. The fixed script *documents* the old
# `rm -rf "$dst"` in a comment; grepping the raw file would match that
# carrier and emit a FALSE finding — itself a §11.4.201 FAIL-bluff.
if sed 's/#.*$//' "$ROOT/scripts/post_update_hook.sh" | grep -q 'rm -rf "\$dst"'; then
	note "post_update_hook.sh install_skills() does \`rm -rf \"\$dst\"\` on <project>/skills/<name> before symlinking. If a consuming project already has a REAL directory of its own at that path (not a symlink), its contents are destroyed without confirmation (§9.2 data-safety / §11.4.122). install_cli_agent_plugins.sh gets this right (it refuses to touch a non-symlink dst and WARNs)."
fi

# C5e — FAIL-CLOSED: a CONST_DIR that is not the constitution must ABORT loudly,
# never silently propagate nothing (§11.4.6). This is what makes the C5c class of
# defect impossible to reintroduce SILENTLY: even if a caller passes the wrong
# dir, the hook must say so and exit non-zero.
bogus_log="$TMP/post_update_bogus.log"
PATH="$SAFE_PATH" CONST_DIR="$TMP" PROJECT_ROOT="$PROJ3" \
	bash "$CREPO/scripts/post_update_hook.sh" >"$bogus_log" 2>&1
bogus_rc=$?
if [ "$bogus_rc" -ne 0 ] && grep -q 'does not look like the constitution root' "$bogus_log"; then
	ok "C5e fail-closed: a CONST_DIR that is not the constitution root ABORTS loudly (rc=$bogus_rc) instead of silently propagating nothing"
else
	no "C5e fail-closed: a bogus CONST_DIR did NOT abort loudly (rc=$bogus_rc) — a mis-resolved constitution root can again propagate NOTHING silently"
	sed 's/^/        | /' "$bogus_log" >&2
fi
# C5f — the git post-merge hook is the PRIMARY automatic path. It does not export
# CONST_DIR, which is CORRECT only because the hook now self-resolves from its own
# location (C5c). Assert the invariant that makes that safe.
PM="$ROOT/scripts/hooks/post-merge"
if [ -f "$PM" ] && grep -q 'POST_UPDATE_HOOK="\${CONST_DIR}/scripts/post_update_hook.sh"' "$PM"; then
	ok "C5f seam: post-merge invokes <constitution>/scripts/post_update_hook.sh by path, and the hook self-resolves CONST_DIR from that path (C5c) — so the §11.4.164 auto-propagation works on a real pull without any env passing"
else
	note "scripts/hooks/post-merge does not invoke the hook via \${CONST_DIR}/scripts/post_update_hook.sh — re-verify that the automatic path still resolves the constitution root correctly."
fi

# ── summary ─────────────────────────────────────────────────────────────────
say ""
if [ "$FINDINGS" -gt 0 ]; then
	say "== FINDINGS ($FINDINGS) — defects/boundaries in scripts owned by another work stream; REPORTED, not patched =="
	printf '%s' "$FINDING_TEXT"
fi
say ""
say "== $SUITE summary: $PASSES passed, $FAILURES failed, $FINDINGS finding(s) =="
[ "$FAILURES" -eq 0 ] || exit 1
exit 0
