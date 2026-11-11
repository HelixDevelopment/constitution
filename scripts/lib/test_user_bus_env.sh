#!/bin/sh
# scripts/lib/test_user_bus_env.sh -- tests of scripts/lib/user_bus_env.sh
# (CON-125 helper; CON-118 follow-ups F110-1 and F110-2).
#
# Each case builds runtime directories in a temp tree, with a real AF_UNIX
# socket (made by python3) or a symlink named `bus` to a root-owned socket,
# and calls ub_user_bus_env in a child sh with a controlled environment.
#   U1 inherited XDG_RUNTIME_DIR holds an owned bus           -> 0 inherited
#   U2 XDG_RUNTIME_DIR unset, standard dir holds an owned bus -> 0 derived
#   U3 XDG_RUNTIME_DIR points at a dir without a bus, the
#      standard dir holds an owned bus (F110-1)               -> 0 derived
#   U4 no bus anywhere                                        -> 1 absent, XDG unchanged
#   U5 the only bus is not owned by the caller (F110-2)       -> 2 foreign
#      (root-owned socket via a symlink; SKIP with a reason when the host
#      has no such socket)
#   U6 a regular file named bus is not a bus                  -> 1 absent
# Usage: sh scripts/lib/test_user_bus_env.sh [<helper>]
# Exit:  0 all passed; 1 a case failed; 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P) || exit 2
LIB=${1:-$HERE/user_bus_env.sh}
[ -f "$LIB" ] || { echo "FATAL: helper not found: $LIB" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 not on PATH" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/ub_env.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
[ -n "$W" ] && [ -d "$W" ] || { echo "FATAL: mktemp gave no directory" >&2; exit 2; }
trap 'bash -c ". \"\$1\" && safe_rm_rf \"\${2:?}\"" _rm "$HERE/safe_rm.sh" "$W" >/dev/null 2>&1' EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS + 1)); echo "ok $*"; }
bad() { FAIL=$((FAIL + 1)); echo "NOT ok $*"; }

mksock() { # <dir>: make <dir>/bus a listening AF_UNIX socket owned by us
    mkdir -p "$1"
    (cd "$1" && python3 -I -c 'import socket; s=socket.socket(socket.AF_UNIX); s.bind("bus")') || return 1
    [ -S "$1/bus" ]
}
# probe <xdg-or-UNSET> <std> -> "rc source xdg"
probe() {
    if [ "$1" = UNSET ]; then
        env -i PATH=/usr/bin:/bin UB_STD_RUNTIME_DIR="$2" sh -c '. "$1"; ub_user_bus_env; r=$?; echo "$r $UB_SOURCE ${XDG_RUNTIME_DIR:-<unset>}"' _ "$LIB"
    else
        env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$1" UB_STD_RUNTIME_DIR="$2" sh -c '. "$1"; ub_user_bus_env; r=$?; echo "$r $UB_SOURCE ${XDG_RUNTIME_DIR:-<unset>}"' _ "$LIB"
    fi
}
want() { # <tag> <got> <want>
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: want '$3' got '$2'"; fi
}

mksock "$W/own_a" || { echo "FATAL: cannot create a socket" >&2; exit 2; }
mksock "$W/own_std" || exit 2
mkdir -p "$W/empty" "$W/none_std" "$W/file_std"
: > "$W/file_std/bus"

want U1_inherited "$(probe "$W/own_a" "$W/none_std")" "0 inherited $W/own_a"
want U2_derived_unset "$(probe UNSET "$W/own_std")" "0 derived $W/own_std"
want U3_derived_over_busless_xdg "$(probe "$W/empty" "$W/own_std")" "0 derived $W/own_std"
want U4_absent "$(probe "$W/empty" "$W/none_std")" "1 absent $W/empty"
want U4b_absent_unset "$(probe UNSET "$W/none_std")" "1 absent <unset>"
want U6_regular_file_is_not_a_bus "$(probe UNSET "$W/file_std")" "1 absent <unset>"

ROOTSOCK=""
for c in /run/dbus/system_bus_socket /var/run/dbus/system_bus_socket /run/systemd/private /run/systemd/notify; do
    if [ -S "$c" ] && [ ! -O "$c" ]; then ROOTSOCK=$c; break; fi
done
if [ -n "$ROOTSOCK" ]; then
    mkdir -p "$W/foreign"; ln -s "$ROOTSOCK" "$W/foreign/bus"
    want U5_foreign_xdg "$(probe "$W/foreign" "$W/none_std")" "2 foreign $W/foreign"
    want U5b_foreign_std "$(probe UNSET "$W/foreign")" "2 foreign <unset>"
    # an owned standard bus wins over a foreign inherited one
    want U5c_owned_std_beats_foreign_xdg "$(probe "$W/foreign" "$W/own_std")" "0 derived $W/own_std"
else
    SKIP=$((SKIP + 1)); echo "SKIP U5: no socket owned by another user on this host reason=topology_unsupported"
fi

echo "RESULT: pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
