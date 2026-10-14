#!/usr/bin/env python3
# scripts/label-sync/hook_mutants.py
#
# Purpose : The §1.1 MUTANT TABLE for the label-sync hooks + wiring stream, and
#           the literal (non-regex) mutator that applies ONE of them to a scratch
#           copy. Kept as data in its own file so every OLD/NEW literal is a plain
#           Python string — no shell-quoting layer between the mutant and the
#           code it mutates (§11.4.201(7c): the path is part of the instrument).
#           Each mutant = (file relative to the constitution root, OLD, NEW, why).
#           OLD must occur EXACTLY ONCE in the file, else the mutant is
#           NOT-APPLIED (exit 1) — a mutant that silently does not apply proves
#           nothing.
# Usage   : hook_mutants.py --list
#           hook_mutants.py --check <constitution-root>     every OLD occurs once?
#           hook_mutants.py --apply <name> <constitution-root>
# Inputs  : argv; the files of the given root (read; --apply writes ONE file).
# Outputs : --list: names; --check: one line per mutant; --apply: the mutated file.
# Exit    : 0 ok | 1 a literal is missing / not unique | 2 usage.
# Side-effects: --apply rewrites one file under the given root (a SCRATCH copy —
#           scripts/label-sync/prove_hook_mutations.sh never passes the real tree).
# Deps    : python3.
# Cross-refs: §1.1, §11.4.201, scripts/label-sync/prove_hook_mutations.sh,
#           review findings 1-11 (docs/label-sync/HOOKS.md §11).
# Classification: universal (§11.4.17).
import sys

LIB = "scripts/label-sync/hooks/label-sync-lib.sh"
PROMPT = "scripts/label-sync/hooks/label-sync-prompt.sh"
REG = "scripts/label-sync/hooks/label-sync-agent-register.sh"
SAS = "scripts/label-sync/hooks/label-sync-subagent-start.sh"
STOP = "scripts/label-sync/hooks/label-sync-stop.sh"
SEND = "scripts/label-sync/hooks/label-sync-session-end.sh"
RHA = "scripts/label-sync/hooks/request_history_append.sh"
INST = "scripts/label-sync/install_label_sync.sh"
WRAP = "scripts/label-sync/toolkit/cma_label_hook.sh"
POST = "scripts/post_update_hook.sh"
SSTART = "scripts/label-sync/hooks/label-sync-session-start.sh"
MSW = "scripts/label-sync/hooks/label-sync-model-switch.sh"
LABELER = "scripts/multitrack/track_branch_label.sh"
BINC = "scripts/label-sync/bincache.sh"
LCTLSH = "scripts/label-sync/labelctl.sh"

M = {
 # ---- the original ten (re-targeted at the current code) ----------------
 "hook_never_registers": (LIB,
    'LS_LABEL="$(ls_ctl "${a[@]}")" || { LS_LABEL=""; ls_dbg "register session failed (source=$src)"; return 1; }',
    'LS_LABEL=""; : # MUTANT: session never registered',
    "SessionStart must register the session entity"),
 "installer_duplicates_entries": (INST, 'if ($p|length)==0 then', 'if true then',
    "re-apply must refresh in place, never append a duplicate"),
 "installer_clobbers_hooks": (INST, '.hooks[$s.event] = (.hooks[$s.event] // [])', '.hooks[$s.event] = []',
    "foreign hooks of the same event must survive"),
 "dry_run_writes": (INST, 'if [ "$apply" = 0 ]; then\n  if [ "$brief" = 1 ]; then',
    'if false; then\n  if [ "$brief" = 1 ]; then', "the default dry-run must write nothing"),
 "invalid_json_accepted": (INST,
    "if ! jq -e 'type==\"object\"' \"$target\" >/dev/null 2>&1; then\n    echo \"install_label_sync: REFUSED",
    "if false; then\n    echo \"install_label_sync: REFUSED", "invalid JSON must be refused"),
 "ledger_double_appends": (RHA, 'exit 3 if $2 eq $sha && $now-$1 < $win;', '1;',
    "a double-delivered prompt must be ONE row"),
 "hook_exits_nonzero": (LIB, "  [ -n \"$out\" ] && printf '%s\\n' \"$out\"\n  exit 0",
    "  [ -n \"$out\" ] && printf '%s\\n' \"$out\"\n  exit 3", "hooks always exit 0"),
 "stop_keeps_phantoms": (STOP,
    '      [ -n "$eid" ] && ls_ctl unregister --id "$eid" >/dev/null\n      rm -f -- "$f"',
    '      rm -f -- "$f"', "Stop must unregister never-started registrations"),
 "wrapper_never_publishes": (WRAP, '  _cma_label_publish "$alias"\n}', '  :\n}',
    "the toolkit launch must publish alias_switch"),
 # ---- review finding 1: per-session binding --------------------------------
 "session_follows_active": (LIB,
    'if [ -n "$alias" ]; then a+=(--alias "$alias" --follow-active false); else',
    'if [ -n "$alias" ]; then a+=(--alias "$alias" --follow-active true); else',
    "F1: a session is PINNED to its derived alias"),
 "prompt_unpins_session": (PROMPT, '[ -n "$alias" ] && u+=(--alias "$alias" --follow-active false)',
    '[ -n "$alias" ] && u+=(--alias "$alias" --follow-active true)',
    "F1: the prompt hook re-asserts the pinned binding"),
 "hook_writes_active": (LIB,
    'ls_dbg "register session failed (source=$src)"; return 1; }\n  return 0',
    'ls_dbg "register session failed (source=$src)"; return 1; }\n  [ -n "$alias" ] && ls_ctl switch-alias --alias "$alias" >/dev/null\n  return 0',
    "F1: hooks never write the global active alias"),
 # ---- reviewer survivors (finding 10) --------------------------------------
 "ledger_shared_dedupe_key": (RHA, 'last="$base/ledger-last/${sid:-nosession}"', 'last="$base/ledger-last/nosession"',
    "dedupe is per session: the same text from two sessions is two rows"),
 "session_end_keeps_pending": (SEND, '  ls_drop_pending_dir "$LS_SID"', '  : # MUTANT',
    "SessionEnd drops the session's pending registrations"),
 # A step returning 1 is now isolated by run_step (review-2 C), so a
 # `return 1` mutant is equivalent; what still aborts the hook is an `exit`,
 # which no layer can isolate — and run_step itself (run_step_propagates_failure).
 "posthook_4c_aborts_hook": (POST, '        WARNINGS+=("install_label_sync.sh exited $rc")\n        return 0',
    '        WARNINGS+=("install_label_sync.sh exited $rc")\n        exit 1',
    "step 4c never aborts post_update_hook.sh"),
 "run_step_propagates_failure": (POST, '        WARNINGS+=("step $fn exited $rc")\n    fi\n    return 0',
    '        WARNINGS+=("step $fn exited $rc")\n    fi\n    return "$rc"',
    "review-2 C: a failing step is recorded and the next steps still run (set -e)"),
 "uninstall_removes_foreign_statusline": (INST,
    '(if (.statusLine != null) and ((.statusLine == $sl) or ((.statusLine.command // "")|contains("label-sync"))) then del(.statusLine) else . end)',
    '(if .statusLine != null then del(.statusLine) else . end)',
    "--uninstall removes OUR statusLine only"),
 "subagent_pairing_newest_first": (SAS, '  if [ "$n" -ne 1 ]; then', '  if [ "$n" -lt 1 ]; then',
    "F4: >=2 candidates => no guess (the mutant pairs the last/newest one)"),
 "nested_parent_ignored": (REG, '    [ -n "$pm" ] && parent="$pm"', '    :',
    "a dispatch from inside a paired subagent is parented to it"),
 # ---- one mutant per new mechanism ----------------------------------------
 "id_validation_dropped": (LIB, 'def okid: type=="string" and test("\\\\A[A-Za-z0-9_-]{1,128}\\\\z");',
    'def okid: type=="string";', "F3: stdin ids are validated (path traversal)"),
 "pairing_reentrant": (SAS, '  [ -e "$map" ] && return 0', '  :',
    "F5: a repeated SubagentStart never re-pairs an agent"),
 "pending_time_keyed": (REG, '>"$LS_HOOKSTATE/pending/$LS_SID/$tuid" 2>/dev/null',
    '>"$LS_HOOKSTATE/pending/$LS_SID/$(date +%s%N)-$tuid" 2>/dev/null',
    "F5: pending registrations keyed by tool_use_id (double delivery = one)"),
 "ledger_failure_silent": (RHA, '  RHA_KIND="$kind" rha_lost_row "$sid" "$8"', '  return 1 # MUTANT\n  RHA_KIND="$kind" rha_lost_row "$sid" "$8"',
    "F2: a failed append still leaves a 'lost' row + counter"),
 "ledger_auto_creates": (RHA, '  [ -n "$RHA_LEDGER" ] || return 1                 # opt-in only: nothing is invented',
    '  [ -n "$RHA_LEDGER" ] || { [ -d "${CLAUDE_PROJECT_DIR:-/nonexistent}/docs/requests" ] && RHA_LEDGER="$CLAUDE_PROJECT_DIR/docs/requests/history.jsonl"; } || return 1',
    "F7: no ledger without an explicit opt-in"),
 "redaction_github_dropped": (RHA, '$n += ($t =~ s/\\bgh[pousr]_[A-Za-z0-9]{20,}/[REDACTED:github-token]/g) || 0;', '$n += 0;',
    "F7: GitHub tokens are redacted before the append"),
 "md_twin_unbounded": (RHA, 'if (-s $md > $mdmax) {', 'if (0) {',
    "F11: the markdown twin is not rewritten above its size bound"),
 "payload_model_ignored": (LIB, '[ -n "${LS_PAYLOAD_MODEL:-}" ] && model="$(ls_model_short "$LS_PAYLOAD_MODEL")"', ':',
    "F11: SessionStart's own model wins over the transcript lookup"),
 "lock_timeout_dropped": (LIB, '    "$LS_CTL_BIN" --lock-timeout "$lt" "$@" 2>/dev/null', '    "$LS_CTL_BIN" "$@" 2>/dev/null',
    "F9: every labelctl call has a short writer-lock bound"),
 "posthook_hooks_unfiltered": (POST, '            *) info "Not a git hook name — not installed: ${hook_name}"; continue ;;', '            *) ;;',
    "F6: only git hook names are copied into .git/hooks"),
 "posthook_nongit_aborts": (POST, '        WARNINGS+=("git hooks not installed: $PROJECT_ROOT is not a git work tree")\n        return 0',
    '        WARNINGS+=("git hooks not installed: $PROJECT_ROOT is not a git work tree")\n        exit 1',
    "F6: a non-git / worktree consumer never aborts the hook"),
 "installer_drops_timeout": (INST, '          | .timeout = ($o.timeout // $s.hook.timeout)', '          | .timeout = $s.hook.timeout',
    "F8: an operator-set timeout survives a refresh"),
 "installer_breaks_symlink": (INST, 'mv -- "$tmp" "$real" ||', 'mv -- "$tmp" "$target" ||',
    "F8: a symlinked settings.json stays a symlink"),
 "installer_metachar_accepted": (INST, '    if bad_path "$_p"; then', '    if false; then',
    "F8: a path with shell metacharacters is refused"),
 "installer_project_statusline_unforced": (INST,
    'if [ "$uninstall" = 0 ] && [ "$wire_sl" = 1 ] && [ "$scope" = project ] && [ "$force_sl" = 0 ]; then',
    'if false; then', "F8: a project-scope statusLine needs --force-statusline"),
 "installer_both_scopes_allowed": (INST, '    if [ "$apply" = 1 ] && [ "$allow_both" = 0 ]; then', '    if false; then',
    "F5: --apply refused while the other scope is wired"),
 "installer_unlocked": (INST, '    if ! flock -w "${LABEL_SYNC_INSTALL_LOCK_WAIT:-10}" 8; then', '    if false; then',
    "F8: the read-modify-write is serialised"),
 "installer_model_switch_unchecked": (INST, '  [ "$with_model" = 1 ] && req_hooks="$req_hooks label-sync-model-switch"', '  :',
    "F8: --with-model-switch requires the script to exist"),
 # ---- second review (findings 1, 3, 10, 13, C, D, E, L) ----------------
 "emit_context_no_quote_escape": (LIB, r't="${t//\\/\\\\}"; t="${t//\"/\\\"}"; ', r't="${t//\\/\\\\}"; ',
    "10 (reviewer B2): a double quote in a branch must be JSON-escaped"),
 "labeler_keeps_paren": (LABELER, '_x="${_x//)/_}"; _x="${_x// - /_}"', '_x="${_x// - /_}"',
    "1: a ')' in a branch must not end the label"),
 "session_start_always_says_pinned": (SSTART, "  local how=\"follows the operator's active alias: no alias could be derived for this process\"", '  local how="pinned to the alias this session runs under"',
    "1: never misreport 'pinned'"),
 "model_switch_not_recorded": (MSW, '  ls_record_model_switch "$mo"', '  :',
    "3: the switch is recorded"),
 "prompt_ignores_model_switch": (PROMPT, '  ls_switched_model && model="$LS_SWITCH_MODEL"', '  :',
    "3: the recorded switch wins over the pre-switch transcript"),
 "model_switch_never_superseded": (LIB, '      rm -f -- "$f"; return 1           # MUT:msnewer', '      :',
    "3: a NEWER assistant entry supersedes the record"),
 "mcp_dst_parse_check_off": (POST, "    if ! jq -e 'type == \"object\"' \"$mcp_dst\" >/dev/null 2>&1; then", '    if false; then',
    "C: an unparseable consumer .mcp.json is left untouched with a warning"),
 "mcp_path_not_resolved": (POST, '            [ -e "$croot/$str" ] && [ ! -e "$proot/$str" ] || continue', '            continue',
    "D: constitution-relative MCP paths resolved for the consumer"),
 "adapters_step_missing": (POST, '    run_step install_label_sync_adapters', '    :',
    "E: step 4d runs install_adapters.sh"),
 "labelsync_scripts_not_syntax_checked": (POST, '        case "$f" in *.sh) [ -f "${CONST_DIR}/$f" ]', '        case "$f" in *.never) [ -f "${CONST_DIR}/$f" ]',
    "L: label-sync *.sh files get the step-5 syntax check"),
 "bincache_key_shared": (BINC, '    __h=$(( (__h * 33 + __c) & 0xffffffff ))   # MUT:cachekey', '    :   # MUT:cachekey',
    "13: the default cache is keyed per checkout"),
 "bincache_commit_ignored": (LCTLSH, '  [ "$rec" != "$(src_commit)" ]   # MUT:commitstale', '  false   # MUT:commitstale',
    "13: binaries from another commit are stale"),
}


def main(argv):
    if len(argv) >= 2 and argv[1] == "--list":
        print("\n".join(M)); return 0
    if len(argv) == 3 and argv[1] == "--check":
        bad = 0
        for name, (f, old, _new, _why) in M.items():
            try:
                n = open(argv[2] + "/" + f).read().count(old)
            except OSError as e:
                n = -1
            ok = (n == 1)
            bad += 0 if ok else 1
            print(("OK          " if ok else "NOT-UNIQUE  ") + f"{name} ({f}: {n} occurrence(s))")
        return 0 if bad == 0 else 1
    if len(argv) == 4 and argv[1] == "--apply":
        name, root = argv[2], argv[3]
        if name not in M:
            print("unknown mutant " + name); return 2
        f, old, new, _why = M[name]
        p = root + "/" + f
        s = open(p).read()
        if s.count(old) != 1:
            print(f"NOT-APPLIED: literal occurs {s.count(old)} time(s) in {f}"); return 1
        open(p, "w").write(s.replace(old, new, 1))
        print(f); return 0
    print("usage: hook_mutants.py --list | --check ROOT | --apply NAME ROOT"); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
