#!/usr/bin/env bash
# cm_cli_agent_plugins_wired.sh — CM-CLI-AGENT-PLUGINS-WIRED gate (§11.4.140 / §11.4.164).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The constitution ships its action directives (§11.4.140) as NATIVE CLI-agent
# artefacts: a Claude Code plugin (`helix`) whose slash commands are GENERATED
# from actions/registry.yaml, a local marketplace that publishes it, and Agent
# Skills that teach the agent when to reach for them. The auto-load seam is
# scripts/post_update_hook.sh (§11.4.164) → scripts/install_cli_agent_plugins.sh.
#
# This gate asserts NINE invariants that together prove the wiring is REAL —
# a newly-registered directive is provably reachable, no collision is silently
# shadowed, and the auto-load seam actually calls the installer. Every invariant
# is a REAL condition on a REAL artefact (§11.4.201 — no proxy signals: the
# drift check RE-RUNS the generator rather than trusting a mtime/marker).
#
#   1. MARKETPLACE   — .claude-plugin/marketplace.json is valid JSON, lists the
#                      `helix` plugin, and its `source` resolves to a real dir.
#   2. PLUGIN        — plugins/helix/.claude-plugin/plugin.json is valid JSON
#                      with name == "helix".
#   3. COMMAND PAIR  — for EVERY action in the registry (read via the library's
#                      apx_list_actions — the registry is never re-parsed here),
#                      BOTH commands/<lc>.md and commands/default-<lc>.md exist
#                      and are non-empty. This is what makes a newly-registered
#                      directive provably REACHABLE.
#   4. FRONTMATTER   — every generated command file carries YAML frontmatter with
#                      a NON-EMPTY description (an empty one is not loadable).
#   5. CONFLICT NOTE — every action whose registry `slash_conflicts` is non-empty
#                      carries the CONFLICT note in its command file: a bare-name
#                      collision with a host built-in is NEVER silently shadowed.
#   6. SKILLS        — every skill dir with a SKILL.md has `name:` + non-empty
#                      `description:` in frontmatter and an EXECUTABLE register.sh
#                      (and at least MIN_SKILLS such skills exist).
#   7. SCRIPTS       — the generator + the installer exist, are executable, and
#                      are `bash -n` clean (§11.4.67).
#   8. NO DRIFT      — the committed commands are IN SYNC with the registry: the
#                      generator is re-run into a temp copy (commands dir emptied
#                      first, so a STALE leftover command is caught too) and the
#                      file SET + every file's sha256 must match byte-for-byte.
#                      A stale/hand-edited/leftover command set FAILs.
#   9. AUTOLOAD SEAM — scripts/post_update_hook.sh's install_action_plugins()
#                      actually CALLS install_cli_agent_plugins.sh — the §11.4.164
#                      seam is wired, not merely present.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash scripts/gates/cm_cli_agent_plugins_wired.sh [--root <constitution-root>]
#                                                    [--min-skills N] [--quiet]
#   --root lets the paired §1.1 mutation test point the gate at a MUTATED COPY in
#   a temp dir, so the REAL tree is never mutated (§11.4.84).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   <root>/.claude-plugin/marketplace.json, <root>/plugins/helix/**,
#   <root>/actions/registry.yaml, <root>/skills/*/SKILL.md,
#   <root>/scripts/{action_prefix_lib,generate_agent_prefix_commands,
#   install_cli_agent_plugins,post_update_hook}.sh
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per invariant on stdout; a final verdict line.
#   Exit 0 — every invariant holds. Exit 1 — one or more FAILed.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE on the repo. Invariant 8 works exclusively inside a `mktemp -d` sandbox
#   removed by the EXIT trap (§11.4.14). The gate never writes into <root>.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, python3 (JSON + registry field reads), sha256sum, mktemp, cp, find.
#   Parses clean under BOTH `bash -n` and `sh -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (action-prefix system + the 5 forms + the slash conflict rule) ·
#   §11.4.164 (post-update auto-propagation seam) · §11.4.75 (mechanical
#   enforcement) · §11.4.201 (a guard asserts the REAL condition) ·
#   §11.4.28/§11.4.177 (decoupling — inherited by reference) · §11.4.67
#   (parseability) · §1.1 (paired mutation: cm_cli_agent_plugins_wired_mutation_test.sh)
#
# Classification: universal (§11.4.17)
# Last verified: 2026-07-15
set -u

GATE="CM-CLI-AGENT-PLUGINS-WIRED"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../.." >/dev/null 2>&1 && pwd)
MIN_SKILLS=3
QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--root)       shift; ROOT="$1" ;;
		--min-skills) shift; MIN_SKILLS="$1" ;;
		--quiet)      QUIET=1 ;;
		-h|--help)    sed -n '3,60p' "$0"; exit 0 ;;
		*)            echo "$GATE: unknown arg: $1" >&2; exit 2 ;;
	esac
	shift || true
done

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
pass() { say "  PASS  [$GATE] $*"; }
fail() { printf '  FAIL  [%s] %s\n' "$GATE" "$*" >&2; FAILS=$((FAILS + 1)); }

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

PLUGIN_NAME="helix"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
PLUGIN_JSON="$ROOT/plugins/$PLUGIN_NAME/.claude-plugin/plugin.json"
CMD_DIR="$ROOT/plugins/$PLUGIN_NAME/commands"
PLUGIN_README="$ROOT/plugins/$PLUGIN_NAME/README.md"
REGISTRY="$ROOT/actions/registry.yaml"
LIB="$ROOT/scripts/action_prefix_lib.sh"
GENERATOR="$ROOT/scripts/generate_agent_prefix_commands.sh"
INSTALLER="$ROOT/scripts/install_cli_agent_plugins.sh"
HOOK="$ROOT/scripts/post_update_hook.sh"

say "== $GATE (root: $ROOT) =="

# ── helpers ──────────────────────────────────────────────────────────────────
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Registry field of one action, via the SAME python+yaml path the generator uses
# (the registry is DATA — never hand-parsed here). Lists print space-separated.
reg_field() {
	python3 - "$REGISTRY" "$1" "$2" <<'PYEOF' 2>/dev/null || true
import sys
try:
    import yaml
except Exception:
    sys.exit(0)
reg, name, field = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(reg) as fh:
        doc = yaml.safe_load(fh) or {}
except Exception:
    sys.exit(0)
for a in (doc.get("actions") or []):
    if a.get("name") == name:
        v = a.get(field)
        if v is None:
            break
        if isinstance(v, (list, tuple)):
            print(" ".join(str(x) for x in v))
        else:
            print(" ".join(str(v).split()))
        break
PYEOF
}

# Non-empty `description:` inside the leading `---` YAML frontmatter of a file.
fm_description() {
	python3 - "$1" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
try:
    lines = open(p, encoding="utf-8").read().splitlines()
except Exception:
    sys.exit(0)
if not lines or lines[0].strip() != "---":
    sys.exit(0)
for i in range(1, len(lines)):
    s = lines[i].strip()
    if s == "---":
        break
    if s.startswith("description:"):
        val = s.split(":", 1)[1].strip().strip('"').strip("'").strip()
        if val:
            print(val)
        break
PYEOF
}

# Non-empty `name:` inside frontmatter (same shape as fm_description).
fm_name() {
	python3 - "$1" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
try:
    lines = open(p, encoding="utf-8").read().splitlines()
except Exception:
    sys.exit(0)
if not lines or lines[0].strip() != "---":
    sys.exit(0)
for i in range(1, len(lines)):
    s = lines[i].strip()
    if s == "---":
        break
    if s.startswith("name:"):
        val = s.split(":", 1)[1].strip().strip('"').strip("'").strip()
        if val:
            print(val)
        break
PYEOF
}

# ── Invariant 1 — marketplace.json ───────────────────────────────────────────
if [ ! -f "$MARKETPLACE" ]; then
	fail "1/marketplace: MISSING $MARKETPLACE"
else
	mp_src=$(python3 - "$MARKETPLACE" "$PLUGIN_NAME" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    doc = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
for p in (doc.get("plugins") or []):
    if p.get("name") == sys.argv[2]:
        print(p.get("source") or "")
        break
PYEOF
)
	if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$MARKETPLACE" >/dev/null 2>&1; then
		fail "1/marketplace: INVALID JSON: $MARKETPLACE"
	elif [ -z "$mp_src" ]; then
		fail "1/marketplace: plugin '$PLUGIN_NAME' NOT listed (or has no source) in $MARKETPLACE"
	else
		mp_dir="$mp_src"
		case "$mp_dir" in /*) : ;; *) mp_dir="$ROOT/${mp_dir#./}" ;; esac
		if [ -d "$mp_dir" ]; then
			pass "1/marketplace: valid JSON; plugin '$PLUGIN_NAME' → '$mp_src' (dir exists)"
		else
			fail "1/marketplace: plugin '$PLUGIN_NAME' source '$mp_src' does NOT resolve to a directory ($mp_dir)"
		fi
	fi
fi

# ── Invariant 2 — plugin manifest ────────────────────────────────────────────
if [ ! -f "$PLUGIN_JSON" ]; then
	fail "2/plugin: MISSING $PLUGIN_JSON"
elif ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PLUGIN_JSON" >/dev/null 2>&1; then
	fail "2/plugin: INVALID JSON: $PLUGIN_JSON"
else
	pj_name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$PLUGIN_JSON" 2>/dev/null || true)
	if [ "$pj_name" = "$PLUGIN_NAME" ]; then
		pass "2/plugin: valid JSON; name == \"$PLUGIN_NAME\""
	else
		fail "2/plugin: name is '$pj_name', expected '$PLUGIN_NAME'"
	fi
fi

# ── action list (from the library — never a hand-rolled YAML parse) ──────────
ACTIONS=""
if [ ! -f "$LIB" ]; then
	fail "3/commands: library MISSING: $LIB"
elif [ ! -f "$REGISTRY" ]; then
	fail "3/commands: registry MISSING: $REGISTRY"
else
	ACTIONS=$(HELIX_ACTION_REGISTRY="$REGISTRY" bash -c '. "$1" && apx_list_actions' _ "$LIB" 2>/dev/null || true)
fi

# ── Invariant 3 — command pair per action; Invariant 5 — conflict note ───────
if [ -z "$ACTIONS" ]; then
	fail "3/commands: apx_list_actions returned NO actions (registry unreadable?)"
else
	n_act=0; miss=0; conf_checked=0; conf_bad=0
	for a in $ACTIONS; do
		n_act=$((n_act + 1))
		l=$(lc "$a")
		for f in "$CMD_DIR/$l.md" "$CMD_DIR/default-$l.md"; do
			if [ ! -s "$f" ]; then
				fail "3/commands: action $a — MISSING or EMPTY command file: $f"
				miss=$((miss + 1))
			fi
		done
		conflicts=$(reg_field "$a" slash_conflicts)
		if [ -n "$conflicts" ]; then
			conf_checked=$((conf_checked + 1))
			if [ -s "$CMD_DIR/$l.md" ] && grep -q 'CONFLICT (registry `slash_conflicts`)' "$CMD_DIR/$l.md"; then
				: # note present — the collision is declared, never silently shadowed
			else
				fail "5/conflict: action $a declares slash_conflicts='$conflicts' but $CMD_DIR/$l.md carries NO CONFLICT note"
				conf_bad=$((conf_bad + 1))
			fi
		fi
	done
	[ "$miss" -eq 0 ] && pass "3/commands: all $n_act action(s) have BOTH <name>.md and default-<name>.md (non-empty)"
	if [ "$conf_checked" -eq 0 ]; then
		pass "5/conflict: no action declares slash_conflicts (nothing to shadow)"
	elif [ "$conf_bad" -eq 0 ]; then
		pass "5/conflict: all $conf_checked colliding action(s) carry the CONFLICT note"
	fi
fi

# ── Invariant 4 — frontmatter description on every generated command ─────────
if [ ! -d "$CMD_DIR" ]; then
	fail "4/frontmatter: command dir MISSING: $CMD_DIR"
else
	n_cmd=0; fm_bad=0
	for f in "$CMD_DIR"/*.md; do
		[ -f "$f" ] || continue
		n_cmd=$((n_cmd + 1))
		if [ -z "$(fm_description "$f")" ]; then
			fail "4/frontmatter: $f has NO valid YAML frontmatter with a non-empty description"
			fm_bad=$((fm_bad + 1))
		fi
	done
	if [ "$n_cmd" -eq 0 ]; then
		fail "4/frontmatter: NO command files in $CMD_DIR"
	elif [ "$fm_bad" -eq 0 ]; then
		pass "4/frontmatter: all $n_cmd command file(s) have frontmatter with a non-empty description"
	fi
fi

# ── Invariant 6 — skills (SKILL.md frontmatter + executable register.sh) ─────
if [ ! -d "$ROOT/skills" ]; then
	fail "6/skills: MISSING $ROOT/skills"
else
	n_sk=0; sk_bad=0
	for d in "$ROOT"/skills/*/; do
		[ -d "$d" ] || continue
		[ -f "${d}SKILL.md" ] || continue   # only real Agent Skills are in scope
		n_sk=$((n_sk + 1))
		sk=$(basename "$d")
		[ -n "$(fm_name "${d}SKILL.md")" ] || { fail "6/skills: $sk — SKILL.md frontmatter has no non-empty 'name:'"; sk_bad=$((sk_bad + 1)); }
		[ -n "$(fm_description "${d}SKILL.md")" ] || { fail "6/skills: $sk — SKILL.md frontmatter has no non-empty 'description:'"; sk_bad=$((sk_bad + 1)); }
		[ -f "${d}register.sh" ] || { fail "6/skills: $sk — register.sh MISSING"; sk_bad=$((sk_bad + 1)); continue; }
		[ -x "${d}register.sh" ] || { fail "6/skills: $sk — register.sh is NOT executable"; sk_bad=$((sk_bad + 1)); }
	done
	if [ "$n_sk" -lt "$MIN_SKILLS" ]; then
		fail "6/skills: only $n_sk SKILL.md skill(s) — expected >= $MIN_SKILLS"
	elif [ "$sk_bad" -eq 0 ]; then
		pass "6/skills: all $n_sk SKILL.md skill(s) have name+description frontmatter and an executable register.sh"
	fi
fi

# ── Invariant 7 — generator + installer exist, executable, bash -n clean ─────
sc_bad=0
for s in "$GENERATOR" "$INSTALLER"; do
	if [ ! -f "$s" ]; then
		fail "7/scripts: MISSING $s"; sc_bad=$((sc_bad + 1)); continue
	fi
	[ -x "$s" ] || { fail "7/scripts: NOT executable: $s"; sc_bad=$((sc_bad + 1)); }
	bash -n "$s" 2>/dev/null || { fail "7/scripts: bash -n FAILED: $s"; sc_bad=$((sc_bad + 1)); }
done
[ "$sc_bad" -eq 0 ] && pass "7/scripts: generator + installer present, executable, bash -n clean"

# ── Invariant 8 — NO DRIFT: regenerate into a temp copy and diff ─────────────
# Real condition (§11.4.201): the generator is actually RE-RUN from the registry
# into a clean sandbox; the committed command SET and every file's sha256 must
# match. Catches a stale leftover command (the generator does not prune) AND a
# hand-edited command AND a registry row whose command was never regenerated.
if [ ! -f "$GENERATOR" ] || [ ! -f "$LIB" ] || [ ! -f "$REGISTRY" ] || [ ! -d "$CMD_DIR" ]; then
	fail "8/drift: cannot run drift check — generator/lib/registry/commands missing"
else
	TMP=$(mktemp -d) || { fail "8/drift: mktemp failed"; TMP=""; }
	if [ -n "$TMP" ]; then
		mkdir -p "$TMP/scripts" "$TMP/actions" "$TMP/plugins/$PLUGIN_NAME/commands"
		cp "$LIB" "$GENERATOR" "$TMP/scripts/" 2>/dev/null || true
		cp "$REGISTRY" "$TMP/actions/registry.yaml" 2>/dev/null || true
		# NOTE: the sandbox commands dir starts EMPTY on purpose — a leftover file
		# in the real tree that the registry no longer produces then shows up as an
		# extra file in the SET diff below.
		if ( unset HELIX_ACTION_REGISTRY; bash "$TMP/scripts/generate_agent_prefix_commands.sh" ) >/dev/null 2>&1; then
			real_list=$( (cd "$CMD_DIR" && ls -1 *.md 2>/dev/null) | sort )
			gen_list=$( (cd "$TMP/plugins/$PLUGIN_NAME/commands" && ls -1 *.md 2>/dev/null) | sort )
			if [ "$real_list" != "$gen_list" ]; then
				fail "8/drift: command SET differs from a fresh generation (stale/extra/missing file)"
				printf '        committed: %s\n' "$(printf '%s' "$real_list" | tr '\n' ' ')" >&2
				printf '        generated: %s\n' "$(printf '%s' "$gen_list" | tr '\n' ' ')" >&2
			else
				drift=0
				for f in $gen_list; do
					h1=$(sha256sum "$CMD_DIR/$f" | cut -d' ' -f1)
					h2=$(sha256sum "$TMP/plugins/$PLUGIN_NAME/commands/$f" | cut -d' ' -f1)
					if [ "$h1" != "$h2" ]; then
						fail "8/drift: $f differs from a fresh generation (stale or hand-edited)"
						drift=$((drift + 1))
					fi
				done
				if [ -f "$TMP/plugins/$PLUGIN_NAME/README.md" ] && [ -f "$PLUGIN_README" ]; then
					h1=$(sha256sum "$PLUGIN_README" | cut -d' ' -f1)
					h2=$(sha256sum "$TMP/plugins/$PLUGIN_NAME/README.md" | cut -d' ' -f1)
					if [ "$h1" != "$h2" ]; then
						fail "8/drift: plugins/$PLUGIN_NAME/README.md differs from a fresh generation"
						drift=$((drift + 1))
					fi
				fi
				[ "$drift" -eq 0 ] && pass "8/drift: committed commands + plugin README are byte-identical to a fresh generation from the registry"
			fi
		else
			fail "8/drift: the generator FAILED to run in the sandbox"
		fi
	fi
fi

# ── Invariant 9 — the §11.4.164 auto-load seam actually calls the installer ──
if [ ! -f "$HOOK" ]; then
	fail "9/autoload: MISSING $HOOK"
else
	body=$(awk '/^install_action_plugins\(\)/,/^}/' "$HOOK" 2>/dev/null || true)
	if [ -z "$body" ]; then
		fail "9/autoload: $HOOK has NO install_action_plugins() function"
	elif printf '%s\n' "$body" | grep -q 'install_cli_agent_plugins\.sh'; then
		if grep -qE '^[[:space:]]*(run_step[[:space:]]+)?install_action_plugins$' "$HOOK"; then
			pass "9/autoload: post_update_hook.sh install_action_plugins() calls install_cli_agent_plugins.sh AND is invoked from main()"
		else
			fail "9/autoload: install_action_plugins() references the installer but is NEVER invoked in $HOOK"
		fi
	else
		fail "9/autoload: install_action_plugins() does NOT reference install_cli_agent_plugins.sh — the §11.4.164 seam is NOT wired"
	fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $GATE: PASS (9/9 invariants) =="
	exit 0
fi
printf '== %s: FAIL (%s failing assertion(s)) ==\n' "$GATE" "$FAILS" >&2
exit 1
