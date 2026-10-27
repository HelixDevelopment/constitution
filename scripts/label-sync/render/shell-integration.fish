# scripts/label-sync/render/shell-integration.fish
#
# Purpose : fish integration for label-sync — the fish counterpart of
#           shell-integration.bash (same cost model and secret policy: command
#           TEXT never leaves this shell; only argv0 is handed to shell-hook.sh,
#           and only if `type -q` resolves it). SOURCE it (instructions only — nothing
#           here edits any config):
#               source /path/to/scripts/label-sync/render/shell-integration.fish
#           fish_prompt  : cheap `seq` compare; on change title.sh --entity <this
#                          shell> (one jq fork); reaps the previous command
#                          entity; heartbeat every LABEL_SYNC_HEARTBEAT s (30).
#           fish_preexec : registers the command (rate-capped by
#                          LABEL_SYNC_CMD_MIN_INTERVAL, default 1 s), background.
#           fish_exit    : unregisters command + shell, background.
# Usage   : see above. Env: LABEL_SYNC_DIR, LABEL_SYNC_LABELCTL,
#           LABEL_SYNC_TITLE_SINK, LABEL_SYNC_CMD_MIN_INTERVAL, LABEL_SYNC_HEARTBEAT.
# Exports : LABEL_SYNC_SHELL_ID only (nothing secret).
# Exit    : sourcing returns 0; handlers never fail the prompt.
# Side-effects: defines event handlers; idempotent.
# Deps    : fish>=3.1, jq (via title.sh), labelctl.sh.
# STATUS  : UNCONFIRMED — written against the fish event API but NOT executed:
#           fish is not installed on the host that built it (§11.4.6). Validate
#           with `fish -n` + a manual prompt cycle before relying on it.
# Cross-refs: §11.4.182, docs/label-sync/RENDERERS.md, shell-hook.sh.
# Classification: universal (§11.4.17).
set -q __ls_loaded; and exit 0
set -g __ls_loaded 1
set -g __ls_rdir (dirname (realpath (status filename)))
if set -q LABEL_SYNC_DIR
    set -g __ls_dir $LABEL_SYNC_DIR
else
    set -g __ls_dir $HOME/.local/state/constitution-label-sync
end
set -g __ls_hook $__ls_rdir/shell-hook.sh
set -q LABEL_SYNC_CMD_MIN_INTERVAL; and set -g __ls_min $LABEL_SYNC_CMD_MIN_INTERVAL; or set -g __ls_min 1
set -q LABEL_SYNC_HEARTBEAT; and set -g __ls_hb $LABEL_SYNC_HEARTBEAT; or set -g __ls_hb 30
set -q LABEL_SYNC_SHELL_ID; and set -g __ls_parent $LABEL_SYNC_SHELL_ID; or set -g __ls_parent ""
set -g __ls_setsid ""
command -q setsid; and set -g __ls_setsid setsid
set -gx LABEL_SYNC_SHELL_ID shell-(string replace -ra '[^A-Za-z0-9.-]' - (hostname))-$fish_pid-(date +%s)
set -g __ls_seen ""
set -g __ls_first 1
set -g __ls_cmd_id ""
set -g __ls_n 0
set -g __ls_cmd_at -9999
set -g __ls_hb_at (date +%s)

function __ls_bg
    command $__ls_setsid $argv >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null
end

function __ls_prompt --on-event fish_prompt
    if test -n "$__ls_cmd_id"
        __ls_bg $__ls_hook cmd-end --id $__ls_cmd_id
        set -g __ls_cmd_id ""
    end
    set -l s ""
    if test -r $__ls_dir/seq
        read -l s <$__ls_dir/seq 2>/dev/null
    end
    if test $__ls_first -eq 1; or begin test -n "$s"; and test "$s" != "$__ls_seen"; end
        set -g __ls_first 0
        set -g __ls_seen $s
        if set -q LABEL_SYNC_TITLE_SINK
            $__ls_rdir/title.sh --entity $LABEL_SYNC_SHELL_ID --sink $LABEL_SYNC_TITLE_SINK 2>/dev/null
        else
            $__ls_rdir/title.sh --entity $LABEL_SYNC_SHELL_ID 2>/dev/null
        end
    end
    set -l now (date +%s)
    if test (math $now - $__ls_hb_at) -ge $__ls_hb
        set -g __ls_hb_at $now
        __ls_bg $__ls_hook shell-beat --id $LABEL_SYNC_SHELL_ID
    end
end

function __ls_preexec --on-event fish_preexec
    set -l now (date +%s)
    test (math $now - $__ls_cmd_at) -lt $__ls_min; and return 0
    set -g __ls_cmd_at $now
    set -g __ls_n (math $__ls_n + 1)
    set -g __ls_cmd_id $LABEL_SYNC_SHELL_ID-c$__ls_n
    # the command TEXT never leaves this shell: only a resolvable argv0 is passed
    set -l a0 '?'
    for w in (string split -n ' ' -- $argv[1])
        if string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' -- $w
            string match -qr '["\'`$\\\\]' -- $w; and break
            continue
        end
        string match -qr '["\'`$\\\\(){}<>|;&]' -- $w; and break
        type -q -- $w; and set a0 $w
        break
    end
    __ls_bg $__ls_hook cmd-start --id $__ls_cmd_id --parent $LABEL_SYNC_SHELL_ID --pid $fish_pid --cwd $PWD --argv0 $a0
end

function __ls_exit --on-event fish_exit
    test -n "$__ls_cmd_id"; and __ls_bg $__ls_hook cmd-end --id $__ls_cmd_id
    __ls_bg $__ls_hook shell-end --id $LABEL_SYNC_SHELL_ID
end

__ls_bg $__ls_hook shell-start --id $LABEL_SYNC_SHELL_ID --pid $fish_pid --cwd $PWD --parent "$__ls_parent"
