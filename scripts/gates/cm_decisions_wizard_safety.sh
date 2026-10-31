#!/usr/bin/env bash
# cm_decisions_wizard_safety.sh — CM-DECISIONS-WIZARD-SAFETY gate (§11.4.10, §11.4.35, §11.4.287).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Functional proof that the decisions wizard, run for real in a throwaway project, writes ONLY its own files:
# .constitution/*, the managed blocks of existing CLAUDE.md/AGENTS.md, and .constitution-install-backup/**.
# It must never touch .claude/settings.json (even with agents.settings_json_consent=true), never write outside
# the project (a --doc ../ attempt must be refused), never store a secret-like value, and never change text
# outside its markers. It also attacks --export (onto CLAUDE.md, into .git/), --doc .git/config and a
# newline-terminated key, all of which must be refused. Positive control: the run must actually write decisions.yml and the block (a wizard
# that writes nothing would otherwise "pass" every absence check, §11.4.273).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_decisions_wizard_safety.sh        Env: DECISIONS_CLI (default: the wizard next to this gate).
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (wizard missing or positive control failed) · 64 usage error.
#
# ── Side-effects / dependencies ───────────────────────────────────────────
#   Everything happens in a mktemp -d removed with safe_rm_rf; bash, git, python3, PyYAML, sha256sum.
#   Paired mutation test: cm_decisions_wizard_safety_mutation_test.sh. Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-DECISIONS-WIZARD-SAFETY"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
cli="${DECISIONS_CLI:-$const/scripts/decisions/constitution_decisions.sh}"
case "${1:-}" in "") ;; -h|--help) sed -n 2,20p "${BASH_SOURCE[0]:-$0}"; exit 0 ;; *) echo "$GATE: unknown argument $1" >&2; exit 64 ;; esac
[ -x "$cli" ] || { echo "⚠ $GATE: BLIND (exit 2) — wizard missing: $cli"; exit 2; }
# shellcheck source=../lib/safe_rm.sh
. "$const/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_dec_safety.XXXXXX")" || { echo "⚠ $GATE: BLIND — mktemp failed"; exit 2; }
trap 'safe_rm_rf "${tmp:?}"' EXIT
export CONSTITUTION_DECISIONS_USER_FILE="$tmp/userconf/decisions.yml"
p="$tmp/proj"; mkdir -p "$p/submodules/constitution" "$p/.claude" "$tmp/outside"
git -C "$p" init -q
printf '# Proj\n\nBefore text.\n' >"$p/CLAUDE.md"; printf '# Agents\n' >"$p/AGENTS.md"
printf '{"hooks":{}}\n' >"$p/.claude/settings.json"; printf 'outside\n' >"$tmp/outside/doc.md"
snap() { (cd "$1" && find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 sha256sum) ; }
snap "$tmp/outside" >"$tmp/out.before"; s_before="$(sha256sum <"$p/.claude/settings.json")"
secret="sk-$(printf 'Z%.0s' $(seq 1 36))"
"$cli" --project-root "$p" --non-interactive --set agents.settings_json_consent=true --set agents.claude.wiring=consent \
  --set calibration.floor=0.95 >"$tmp/run1.log" 2>&1; r1=$?
# positive control: the real run must have written its own files
if [ "$r1" != 0 ] || ! grep -q 'calibration.floor: 0.95' "$p/.constitution/decisions.yml" 2>/dev/null \
   || ! grep -q 'BEGIN constitution-decisions' "$p/CLAUDE.md"; then
  echo "⚠ $GATE: BLIND (exit 2) — positive control failed (rc=$r1): the wizard did not write its own files"; exit 2
fi
"$cli" --project-root "$p" --non-interactive --set "llmctl.download_profile=$secret" >"$tmp/run2.log" 2>&1; r2=$?
"$cli" --project-root "$p" --non-interactive --doc ../outside/doc.md --set hosted.allowed=false >"$tmp/run3.log" 2>&1; r3=$?
c_before="$(sha256sum <"$p/CLAUDE.md")"; g_before="$(sha256sum <"$p/.git/config")"
"$cli" --project-root "$p" --export CLAUDE.md >"$tmp/run4.log" 2>&1; r4=$?
"$cli" --project-root "$p" --non-interactive --doc .git/config --set hosted.allowed=true >"$tmp/run5.log" 2>&1; r5=$?
"$cli" --project-root "$p" --export .git/exported.yml >"$tmp/run6.log" 2>&1; r6=$?
"$cli" --project-root "$p" --non-interactive --set "question_types.gate.mode
=shadow" >"$tmp/run7.log" 2>&1; r7=$?
fails=()
[ "$r4" = 3 ] || fails+=("--export onto an existing CLAUDE.md not refused (rc=$r4)")
[ "$(sha256sum <"$p/CLAUDE.md")" = "$c_before" ] || fails+=("CLAUDE.md overwritten by --export")
[ "$r5" = 3 ] || fails+=("--doc .git/config not refused (rc=$r5)")
[ "$r6" = 3 ] || fails+=("--export into .git not refused (rc=$r6)")
[ "$(sha256sum <"$p/.git/config")" = "$g_before" ] || fails+=(".git/config modified")
[ ! -e "$p/.git/exported.yml" ] || fails+=("file written into .git")
[ "$r7" = 4 ] || fails+=("newline-terminated key not refused (rc=$r7)")
"$cli" --project-root "$p" --check >/dev/null 2>&1 || fails+=("decisions file no longer passes --check after the attack runs")
[ "$(sha256sum <"$p/.claude/settings.json")" = "$s_before" ] || fails+=("settings.json was modified")
snap "$tmp/outside" >"$tmp/out.after"; cmp -s "$tmp/out.before" "$tmp/out.after" || fails+=("a file outside the project was modified")
[ "$r2" = 4 ] || fails+=("secret-like value not refused (rc=$r2)")
[ "$r3" = 3 ] || fails+=("--doc outside the project not refused (rc=$r3)")
if grep -rqF "$secret" "$p" "$tmp/userconf" "$tmp/run1.log" "$tmp/run2.log" "$tmp/run3.log" 2>/dev/null; then fails+=("secret value written or echoed"); fi
grep -q '^Before text\.$' "$p/CLAUDE.md" && head -1 "$p/CLAUDE.md" | grep -q '^# Proj$' || fails+=("text outside the markers changed")
stray="$(cd "$p" && find . -type f ! -path './.git/*' ! -path './.constitution/*' ! -path './.constitution-install-backup/*' \
  ! -name CLAUDE.md ! -name AGENTS.md ! -path './.claude/settings.json' | sort)"
[ -z "$stray" ] || fails+=("unexpected files written: $(echo "$stray" | tr '\n' ' ')")
if [ "${#fails[@]}" -eq 0 ]; then echo "✓ $GATE: PASS — writes confined to the project's own decision files"; exit 0; fi
msg="$(printf '%s; ' "${fails[@]}")"; echo "✗ $GATE: FAIL — ${msg%; }"; exit 1
