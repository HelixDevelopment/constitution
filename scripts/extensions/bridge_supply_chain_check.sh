#!/usr/bin/env bash
# bridge_supply_chain_check.sh — HXC-159 T-B1.03 Bridge supply-chain refusal check.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Records the measured supply-chain health of every Bridge dependency at the
# ONE place an implementer actually hits it: install-time refusal logic — not
# a note in a document nobody reads before running the installer. This script
# is BOTH a sourceable library (`bridge_supply_chain_verdict`,
# `bridge_supply_chain_refuse_if_unpinned`) a future installer (Phase B2's
# `install_speckit_superpowers_bridge.sh`) calls directly, AND a standalone
# CLI check runnable on its own. The runtime signature this satisfies: "the
# installer refuses a prohibited or unpinned dependency at install time."
#
# The dependency registry below is DATA, re-verified against the live
# upstream on 2026-09-22 (see docs/qa/hxc159-bridge-supply-chain/ for the
# captured `gh api` evidence backing every field) — it is NOT re-derived from
# scratch from the original task brief; it corrects TWO fields the brief's
# 2026-07-29-dated snapshot had gone stale on (SuperSpec's watcher/push-date
# facts) and confirms the rest unchanged.
#
# ── Registry (closed set — extend only with fresh evidence, never guess) ────
#   obra-superpowers        LOW      official marketplace plugin, already installed
#   superspec                MEDIUM   WangX0111/superspec — adoptable, PINNED-ONLY
#                                      (immutable commit SHA; NEVER a branch/tag ref)
#   superb                   HIGH     RbBtSn0w/spec-kit-extensions "superb" —
#                                      community discovery-only catalog entry;
#                                      NOT directly installable without an
#                                      explicit --from <archive-url> AND an
#                                      operator vetting decision (§11.4.66)
#   erophames-superpowers-mcc PROHIBIT erophames/superpowers-mcp — see below
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   Sourced (library use, the intended Phase-B2 installer call shape):
#     . constitution/scripts/extensions/bridge_supply_chain_check.sh
#     bridge_supply_chain_refuse_if_unpinned "superspec" "$REF" || exit 1
#
#   Standalone CLI:
#     bash constitution/scripts/extensions/bridge_supply_chain_check.sh <dep-id> [<ref>]
#     bash constitution/scripts/extensions/bridge_supply_chain_check.sh --list
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   `bridge_supply_chain_verdict <dep-id>`
#     stdout: one line "VERDICT: <RISK> <RECOMMENDATION>"
#     return: 0 unknown-dep-id is NOT possible to return silently — an unknown
#             id is itself refused (exit 3, §11.4.201 conservative default).
#
#   `bridge_supply_chain_refuse_if_unpinned <dep-id> <ref>`
#     stdout/stderr: ALLOW or REFUSE line naming the exact reason.
#     return: 0 = installer may proceed; non-zero = installer MUST refuse.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE. Pure functions over their arguments; no filesystem/network I/O.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash only (POSIX-ish; no python3/jq dependency so it is cheap to `source`
#   from any future installer). Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/tasks.md T-B1.03 · spec.md §7 (FR-049,
#   FR-050) · §11.4.10 (credentials — N/A here, no secrets handled) · §11.4.66
#   (operator vetting decision for HIGH-risk community catalog entries) ·
#   §11.4.99 (latest-source verification — every fact below was re-checked
#   live via `gh api` on 2026-09-22, not carried forward from memory) ·
#   §11.4.111 (resolve by stable name — the whole point of the pin check).
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

# ── the closed registry, as a case statement (bash 3.2-compatible — no
#    associative arrays required, so this sources cleanly on macOS's stock
#    bash too, per this project's cross-platform-parity discipline) ─────────
_bridge_dep_risk() {
	case "$1" in
		obra-superpowers)            echo "LOW" ;;
		superspec)                   echo "MEDIUM" ;;
		superb)                      echo "HIGH" ;;
		erophames-superpowers-mcp)   echo "PROHIBITED" ;;
		*)                           echo "UNKNOWN" ;;
	esac
}

_bridge_dep_requires_immutable_pin() {
	# Dependencies that MUST be installed by an immutable reference (a full
	# commit SHA, or an immutable release-asset URL) — never a mutable branch
	# name, a floating tag, or "latest".
	case "$1" in
		superspec|superb) return 0 ;;
		*)                return 1 ;;
	esac
}

_bridge_dep_reason() {
	case "$1" in
		obra-superpowers)
			echo "Official spec-kit marketplace plugin (obra/superpowers). Already installed in this repo. LOW risk." ;;
		superspec)
			echo "WangX0111/superspec, extension id 'superspec', self-branded 'Superpowers Bridge'. MEDIUM risk: adoptable ONLY pinned to an immutable commit SHA — NEVER the mutable tag-archive URL its own README's quick-install one-liner uses. This repo already installs it as a git submodule pinned to commit c20ac6c1 (verified 2026-09-22), which satisfies the pin requirement." ;;
		superb)
			echo "RbBtSn0w/spec-kit-extensions, extension id 'superb' — a DIFFERENT project from 'superspec' despite both self-branding 'Superpowers Bridge'. Distributed via the speckit-community catalog as discovery-only (NOT directly installable via 'specify extension add superb' without an explicit --from <archive-url>). 12 tagged releases (superpowers-bridge-v1.0.0 .. v1.9.0, re-verified 2026-09-22, still 12), each shipping an immutable superpowers-bridge.zip release asset, and it is the only one of these four dependencies that ships a tests/ directory (re-verified). HIGH risk as-is: MEDIUM-adoptable ONLY if pinned to one specific release-asset URL AND an operator vetting decision is recorded (§11.4.66) — never installed bare from the discovery-only catalog entry." ;;
		erophames-superpowers-mcp)
			echo "erophames/superpowers-mcp. PROHIBITED. No LICENSE file (re-verified 2026-09-22: contents listing carries no LICENSE). Dead — last push 2026-03-15 (re-verified via gh api: pushed_at 2026-03-15T09:04:15Z; today is 2026-09-22, i.e. >6 months, worse than the task brief's earlier '~4.5 months' reading). Per the original research: it git-pulls obra/superpowers DAILY via an unsandboxed execFile call — an unattended auto-update of remote instructions the agent then executes. Worse than having no L5 execution layer at all. NEVER adopt, under any pin." ;;
		*)
			echo "Not in the closed Bridge dependency registry. An unknown/unregistered dependency is REFUSED per §11.4.201's conservative default — extend the registry with fresh, cited evidence before adopting it, never install it unreviewed." ;;
	esac
}

# ── looks-like-an-immutable-reference heuristic ─────────────────────────────
# A full (or reasonably long, >=12 hex chars) git commit SHA, OR an
# https URL containing a versioned release-asset path segment, counts as
# pinned. A bare branch name (main/master/HEAD), a floating tag with no
# accompanying asset URL, or an empty ref does NOT.
_bridge_ref_is_pinned() {
	ref="$1"
	case "$ref" in
		"" ) return 1 ;;
		main|master|HEAD|latest|MAIN|MASTER|LATEST) return 1 ;;
		http*://*/releases/download/*) return 0 ;;
		*)
			# full or abbreviated hex commit SHA (12-40 hex chars, case-insensitive)
			case "$ref" in
				*[!0-9a-fA-F]*) return 1 ;;
				*)
					len=${#ref}
					if [ "$len" -ge 12 ] && [ "$len" -le 40 ]; then
						return 0
					fi
					return 1
					;;
			esac
			;;
	esac
}

# ── public API #1: verdict lookup (never silent on an unknown id) ──────────
bridge_supply_chain_verdict() {
	dep="${1:-}"
	risk=$(_bridge_dep_risk "$dep")
	reason=$(_bridge_dep_reason "$dep")
	case "$risk" in
		LOW)
			echo "VERDICT: LOW — adoptable as-is. $reason"
			return 0
			;;
		MEDIUM)
			echo "VERDICT: MEDIUM — adoptable ONLY pinned to an immutable reference. $reason"
			return 0
			;;
		HIGH)
			echo "VERDICT: HIGH — not adoptable as-is; requires an explicit pinned archive URL AND a recorded operator vetting decision (§11.4.66). $reason"
			return 2
			;;
		PROHIBITED)
			echo "VERDICT: PROHIBITED — never adopt, under any pin or vetting decision. $reason" >&2
			return 1
			;;
		UNKNOWN|*)
			echo "VERDICT: UNKNOWN (unregistered dependency) — REFUSED by conservative default. $reason" >&2
			return 3
			;;
	esac
}

# ── public API #2: the actual install-time refusal function ────────────────
# This is what a Phase-B2 installer calls before doing anything with a
# dependency. Returns 0 ONLY when the installer may proceed.
bridge_supply_chain_refuse_if_unpinned() {
	dep="${1:-}"
	ref="${2:-}"
	risk=$(_bridge_dep_risk "$dep")

	if [ "$risk" = "PROHIBITED" ]; then
		echo "REFUSE: dependency '$dep' is PROHIBITED — $(_bridge_dep_reason "$dep")" >&2
		return 1
	fi
	if [ "$risk" = "UNKNOWN" ]; then
		echo "REFUSE: dependency '$dep' is not in the registry — $(_bridge_dep_reason "$dep")" >&2
		return 3
	fi
	if [ "$risk" = "HIGH" ]; then
		echo "REFUSE: dependency '$dep' is HIGH risk and requires an explicit operator vetting decision before any install attempt (§11.4.66) — this function alone never authorises it. $(_bridge_dep_reason "$dep")" >&2
		return 2
	fi
	if _bridge_dep_requires_immutable_pin "$dep"; then
		if _bridge_ref_is_pinned "$ref"; then
			echo "ALLOW: dependency '$dep' pinned to '$ref' (looks like an immutable commit SHA or release-asset URL)."
			return 0
		else
			echo "REFUSE: dependency '$dep' requires an immutable pin (a full/abbreviated commit SHA >=12 hex chars, or a versioned release-asset URL) — got '$ref', which is not one. $(_bridge_dep_reason "$dep")" >&2
			return 4
		fi
	fi
	echo "ALLOW: dependency '$dep' is LOW risk and does not require pinning."
	return 0
}

bridge_supply_chain_list() {
	for d in obra-superpowers superspec superb erophames-superpowers-mcp; do
		printf '%s: ' "$d"
		bridge_supply_chain_verdict "$d" >/dev/null 2>&1
		echo "$(_bridge_dep_risk "$d")"
	done
}

# ── CLI entry point — only when EXECUTED, never when sourced (so a future
#    installer can `. bridge_supply_chain_check.sh` without side effects). ──
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
	if [ "${1:-}" = "--list" ]; then
		bridge_supply_chain_list
		exit 0
	fi
	if [ $# -lt 1 ]; then
		echo "usage: bridge_supply_chain_check.sh <dep-id> [<ref>]" >&2
		echo "       bridge_supply_chain_check.sh --list" >&2
		exit 2
	fi
	if [ $# -ge 2 ]; then
		bridge_supply_chain_refuse_if_unpinned "$1" "$2"
		exit $?
	fi
	bridge_supply_chain_verdict "$1"
	exit $?
fi
