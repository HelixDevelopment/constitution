#!/usr/bin/env bash
# ============================================================================
# register.sh — skill-catalog / §11.4.272 dynamic skill activation
# host-CLI auto-install seam.
# ============================================================================
# Purpose:
#   Called by post_update_hook.sh's `skills/*/register.sh` bucket
#   (install_skills(): `register="${src}/register.sh"; [ -f "$register" ] &&
#   bash "$register" "$PROJECT_ROOT"`) whenever `constitution/skills/
#   skill-catalog/**` changes in a `git submodule update --remote
#   constitution` pull.
#
#   Root-caused 2026-09-22 (systematic-debugging, CM-CLI-AGENT-PLUGINS-WIRED
#   invariant 6/skills): this file did not previously exist, so a FRESH host
#   pulling this constitution for the first time got the skill-catalog
#   SKILL.md's own documented entry point (`~/.claude-shared/bin/
#   skill-activate`) NOT wired at all -- it only worked on hosts where an
#   operator had hand-installed a copy once, out of band, with no tracked
#   source anywhere in this repository. That directly contradicted this
#   mechanism's own documented promise: "a project WITHOUT the submodule
#   still gets a working command" (§11.4.272 clause G).
#
#   Installs (idempotently) a byte-identical copy of the canonical wrapper
#   ../../scripts/skill_activation/skill-activate-wrapper.sh to
#   ~/.claude-shared/bin/skill-activate -- creating the parent directory if
#   needed, replacing the installed copy only when its content genuinely
#   differs from the canonical source (never touches a file that isn't this
#   wrapper, never removes anything -- §11.4.122). Unlike multitrack's
#   register.sh (which delegates its ENTIRE body to a project-scoped
#   bootstrap script via `exec`), this mechanism is HOST-level and
#   project-agnostic by design (the wrapper itself resolves its target
#   constitution checkout at CALL time, not at install time -- see the
#   wrapper's own `_resolve()`), so there is no project-scoped bootstrap to
#   delegate to; the installation step IS the whole job.
#
# Usage:   bash register.sh <project-root>
# Inputs:  $1 — consuming project root (post_update_hook.sh always passes
#          its own $PROJECT_ROOT here; unused by this script beyond being
#          accepted, since the installed wrapper is host-level, not
#          project-scoped -- accepted anyway to match every sibling
#          register.sh's calling convention).
# Outputs: prints what it did (installed / already up to date / repaired)
#          and exits 0. A HOME resolution failure (extremely unlikely --
#          HOME is required for basically everything else in this
#          environment too) is the only fatal path, per §11.4.201: refuse
#          rather than guess a fallback location.
# Side-effects: writes ~/.claude-shared/bin/skill-activate (creating
#          ~/.claude-shared/bin/ if absent) ONLY when its content differs
#          from the canonical source below. Nothing else on the host is
#          touched.
# Cross-references:
#   constitution/scripts/skill_activation/skill-activate-wrapper.sh
#     (the canonical, single-source-of-truth wrapper content)
#   constitution/scripts/skill_activation/README.md ("## Use" section --
#     documents ~/.claude-shared/bin/skill-activate as the primary entry
#     point this register.sh exists to guarantee)
#   constitution/scripts/post_update_hook.sh (the invoking seam, §11.4.164
#     STEP 2 install_skills())
#   constitution/scripts/gates/cm_cli_agent_plugins_wired.sh (invariant
#     6/skills — the gate this file closes)
# Last verified: 2026-09-22
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
SOURCE="${SCRIPT_DIR}/../../scripts/skill_activation/skill-activate-wrapper.sh"

if [ ! -r "$SOURCE" ]; then
	echo "register.sh (skill-catalog): canonical wrapper source missing: $SOURCE" >&2
	echo "  -> skipping host-CLI install; the constitution checkout may be incomplete." >&2
	exit 1
fi

if [ -z "${HOME:-}" ]; then
	echo "register.sh (skill-catalog): \$HOME is unset — cannot determine the install path." >&2
	echo "  -> refusing to guess a location; skipping host-CLI install." >&2
	exit 1
fi

DEST_DIR="${HOME}/.claude-shared/bin"
DEST="${DEST_DIR}/skill-activate"

mkdir -p "$DEST_DIR" 2>/dev/null || {
	echo "register.sh (skill-catalog): could not create $DEST_DIR — skipping host-CLI install." >&2
	exit 1
}

if [ -f "$DEST" ] && cmp -s "$SOURCE" "$DEST"; then
	echo "register.sh (skill-catalog): $DEST already up to date."
	exit 0
fi

if [ -e "$DEST" ] && [ ! -w "$DEST" ]; then
	echo "register.sh (skill-catalog): $DEST exists and is not writable — leaving it untouched." >&2
	exit 1
fi

cp "$SOURCE" "$DEST" && chmod +x "$DEST"
if [ -f "$DEST" ] && cmp -s "$SOURCE" "$DEST"; then
	echo "register.sh (skill-catalog): installed/repaired $DEST"
	exit 0
fi

echo "register.sh (skill-catalog): install to $DEST did not verify — check permissions." >&2
exit 1
