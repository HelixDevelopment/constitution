# shellcheck shell=sh
# scripts/lib/user_bus_env.sh -- find the caller's own systemd --user bus
# (CON-117, CON-110 follow-ups F110-1/F110-2/F110-3).
#
# A clean environment (env -i, the full-suite runner, cron) carries no
# XDG_RUNTIME_DIR, or one that points somewhere without a bus; `systemctl
# --user` and `systemd-run --user` are then blind although the user manager
# runs. Source this file (POSIX sh, dash, busybox and bash) and call:
#
#   ub_user_bus_env
#
# It never guesses: a bus counts only when "<dir>/bus" is a socket owned by
# the calling user (test -S and test -O, the same rule in every branch).
#   return 0  usable bus found. XDG_RUNTIME_DIR is exported to its directory:
#             kept when the inherited value already has an owned bus there,
#             otherwise set to the standard pam_systemd directory
#             /run/user/<uid> when that holds one (UB_SOURCE=inherited|derived).
#   return 1  no bus socket in either place (UB_SOURCE=absent): the topology
#             is genuinely absent; callers SKIP or refuse with a reason.
#   return 2  a bus socket exists but is not owned by the caller
#             (UB_SOURCE=foreign, UB_BUS_PATH names it): not this user's
#             manager; callers SKIP or refuse with that reason, never use it.
# XDG_RUNTIME_DIR is left untouched on return 1 and 2.
#
# UB_STD_RUNTIME_DIR overrides /run/user/<uid> (for the helper's own test).
#
# Variables set: UB_SOURCE, UB_BUS_PATH. Every other name is prefixed _ub_.

ub_user_bus_env() {
    UB_SOURCE=absent
    UB_BUS_PATH=""
    _ub_std=${UB_STD_RUNTIME_DIR:-/run/user/$(id -u 2>/dev/null)}
    _ub_foreign=""
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        if [ -O "$XDG_RUNTIME_DIR/bus" ]; then
            UB_SOURCE=inherited
            UB_BUS_PATH="$XDG_RUNTIME_DIR/bus"
            export XDG_RUNTIME_DIR
            return 0
        fi
        _ub_foreign="$XDG_RUNTIME_DIR/bus"
    fi
    if [ -S "$_ub_std/bus" ]; then
        if [ -O "$_ub_std/bus" ]; then
            UB_SOURCE=derived
            UB_BUS_PATH="$_ub_std/bus"
            XDG_RUNTIME_DIR=$_ub_std
            export XDG_RUNTIME_DIR
            return 0
        fi
        [ -n "$_ub_foreign" ] || _ub_foreign="$_ub_std/bus"
    fi
    if [ -n "$_ub_foreign" ]; then
        UB_SOURCE=foreign
        UB_BUS_PATH=$_ub_foreign
        return 2
    fi
    return 1
}
