#!/usr/bin/env bash
# scripts/label-sync/render/prove_mutations.sh
#
# Purpose : §1.1 paired-mutation proof for the label-sync RENDERERS. Copies the
#           render dir to a SCRATCH dir, applies ONE mutant per copy, runs
#           tests/test_render.sh against the copy and REQUIRES it to FAIL; a
#           control run of the unmutated copy REQUIRES it to pass. A surviving
#           mutant means the tests do not guard that behaviour.
#           27 mutants: the original 8 (statusline_ignores_snapshot ..
#           labelrun_no_unregister) plus every mutant the 2026-10-12 review saw
#           SURVIVE (no sanitise in statusline / tmux, SIGINT not reset, argv0
#           unrestricted, digest/salt, previous DEBUG trap dropped, PROMPT_COMMAND
#           clobbered) and one per new mechanism (watch sanitise, locale-dependent
#           sanitiser, double Ctrl-C, backstop redaction, $_ clobber, errexit,
#           plain terminal pinned), and the second review's (statusline session
#           preference — reviewer B4 — and the cwd/HEAD refresh of finding 8). The review's "unsalted digest" mutant no longer
#           applies: the digest was removed (finding 7) — digest_recorded and
#           salt_exported guard its return instead.
# Usage   : bash scripts/label-sync/render/prove_mutations.sh [--only <mutant>]
# Inputs  : none (reads the render dir next to this script).
# Outputs : one line per mutant KILLED / SURVIVED / NOT-APPLIED, then a summary.
# Exit    : 0 every mutant killed and control green | 1 a mutant survived or the
#           control failed | 2 environment (no jq/go, copy failure, a mutation
#           that did not change its file) — never a pass.
# Side-effects: temp dir under $TMPDIR (trap-removed); each test run uses its own
#           temp state dir. Never edits the real tree. Heavy (each run ~30-60 s):
#           run niced, one at a time (§12.6/§12.8).
# Deps    : bash, jq, go, sed, cmp, mktemp, timeout.
# Cross-refs: §1.1, §11.4.107(10), §11.4.201, §11.4.18, tests/test_render.sh.
# Classification: universal (§11.4.17).
set -uo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST="$SELF/tests/test_render.sh"
command -v jq >/dev/null 2>&1 && command -v go >/dev/null 2>&1 || { echo "prove_mutations: jq/go missing" >&2; exit 2; }
ONLY=""; [ "${1:-}" = "--only" ] && ONLY=",${2:-},"   # one name or a comma list
TMP="$(mktemp -d "${TMPDIR:-/tmp}/render_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# name|file|sed-expression (must change the file)
MUTANTS=(
  'statusline_ignores_snapshot|statusline.sh|s|if \[ "\$status" = "ok" \] \&\& \[ -n "\$text" \]; then|if false; then|'
  'title_not_refreshed_on_seq|shell-integration.bash|s|\[ "\$s" != "\$__ls_seen_seq" \]|false|'
  'labelrun_swallows_exit|labelrun|s|^exit "\$rc"$|exit 0|'
  'shell_records_full_command|shell-integration.bash|s|--argv0 "\$__ls_a0"|--argv0 "$BASH_COMMAND"|'
  'title_keeps_control_chars|lib.sh|s|^  ls_sanitize_into text "\${1-}" 256$|  text="${1-}"|'
  'statusline_drops_stale_marker|statusline.sh|s|if \$e.stale then " \[stale\]" elif|if false then " [stale]" elif|'
  'tmux_keeps_hash|tmux-status.sh|s|printf .%s\\n. "\${out//#/_}"|printf "%s\\n" "${out}"|'
  'labelrun_no_unregister|labelrun|s|^cleanup() { \[ "\$registered" = 1 \] \&\& .*$|cleanup() { return 0; }|'
  'statusline_no_sanitize|statusline.sh|s|^  ls_sanitize_into text "\$text".*$|  :|'
  'tmux_no_sanitize|tmux-status.sh|s|^ls_sanitize_into out "\$out"; |: ; |'
  'watch_no_sanitize|watch-labels.sh|s|ls_sanitize_into line "\$line" 1024; ||'
  'sanitize_cntrl_only_locale_dependent|lib.sh|s|^ls_sanitize_into() {$|ls_sanitize_into() { printf -v "$1" "%s" "${2//[[:cntrl:]]/}"; return 0;|'
  'labelrun_sigint_not_reset|labelrun|s|^  runner=(env --default-signal=INT,QUIT)$|  runner=()|'
  'labelrun_double_int|labelrun|s|if \[ "\${f\[5\]:-0}" -gt 0 \]|if false|'
  'argv0_unrestricted|shell-integration.bash|s|^    type -t -- "\$w" >/dev/null 2>\&1 \|\| return 0$|    :|'
  'argv0_no_redaction|shell-hook.sh|s|^ls_argv0_clean() {$|ls_argv0_clean() { local w="${1:-?}"; w="${w##*/}"; w="${w//[^A-Za-z0-9._+-]/}"; printf "%s" "${w:0:40}"; return 0;|'
  'salt_exported|shell-integration.bash|s|^export LABEL_SYNC_SHELL_ID=\(.*\)$|export LABEL_SYNC_SHELL_ID=\1\nexport LABEL_SYNC_SALT="${RANDOM}${RANDOM}"|'
  'digest_recorded|shell-hook.sh|s|--source "shell-integration:argv0=\${a0}"|--source "shell-integration:argv0=${a0}:h=0123456789ab"|'
  'debug_trap_clobbers_underscore|shell-integration.bash|s|__ls_trapstr DEBUG "__ls_debug \\"\\$_\\""|__ls_trapstr DEBUG "__ls_debug"|'
  'precmd_errexit|shell-integration.bash|s|{ read -r s <"\$__LS_DIR/seq"; } 2>/dev/null \|\| :|{ read -r s <"$__LS_DIR/seq"; } 2>/dev/null|'
  'prev_debug_trap_dropped|shell-integration.bash|s|if \[ -n "\$p" \]; then __ls_ts=|if false; then __ls_ts=|'
  'prompt_command_clobbered|shell-integration.bash|s|^  PROMPT_COMMAND="\${PROMPT_COMMAND%;};\$__ls_pc"$|  PROMPT_COMMAND="$__ls_pc"|'
  'plain_terminal_pins|shell-hook.sh|s|^    fol=(--follow-active true)$|    fol=()|'
  # --- second review (findings 8, 11) ---
  'statusline_no_session_preference|statusline.sh|s|(map(select(.kind == "session")) + .) \| first|first|'
  'refresh_ignores_cwd|shell-integration.bash|/MUT:refreshcwd/s|__ls_find_head; ch=0|__ls_find_head|'
  'refresh_ignores_head|shell-integration.bash|/MUT:refreshhead/s|__ls_head="\$h"; ch=0;|__ls_head="$h";|'
  'refresh_keeps_stale_branch|shell-hook.sh|s|else clr+=(branch); fi|else :; fi|'
)

run_tests() { RENDER_DIR="$1" nice -n 10 timeout 300 bash "$TEST" >"$2" 2>&1; }

fail=0; killed=0; total=0
CTL="$TMP/control"; mkdir -p "$CTL" && cp -R "$SELF/." "$CTL/" || exit 2
if run_tests "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated copy: tests PASS"
else echo "CONTROL   FAILED — unmutated tests do not pass"; grep -E '^FAIL' "$TMP/control.log" | head; exit 1; fi

for m in "${MUTANTS[@]}"; do
  name="${m%%|*}"; rest="${m#*|}"; file="${rest%%|*}"; expr="${rest#*|}"
  [ -z "$ONLY" ] || case "$ONLY" in *",$name,"*) ;; *) continue ;; esac
  total=$((total+1))
  d="$TMP/$name"; mkdir -p "$d" && cp -R "$SELF/." "$d/" || exit 2
  cp "$d/$file" "$d/$file.orig"
  sed -i "$expr" "$d/$file" || exit 2
  if cmp -s "$d/$file" "$d/$file.orig"; then echo "NOT-APPLIED $name — sed did not change $file"; exit 2; fi
  rm -f "$d/$file.orig"
  if run_tests "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — tests still pass with the mutation"; fail=1
  else
    echo "KILLED    $name  ($(grep -c '^FAIL' "$TMP/$name.log") failing case(s): $(grep '^FAIL' "$TMP/$name.log" | head -2 | cut -c1-70 | tr '\n' ';'))"; killed=$((killed+1))
  fi
done
echo "SUMMARY   $killed/$total mutants killed"
[ "$fail" -eq 0 ] && [ "$killed" -eq "$total" ]
