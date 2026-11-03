#!/usr/bin/env bash
# =============================================================================
# foreign_uid_cause.sh -- print, on ONE line, the MEASURED reason why this host can or cannot give the fastcycle
# safepath / supervisor suites a real foreign uid (a subordinate uid through `unshare --map-users=auto`).
#
# Why (carry review round 1, F5): the suites printed "no subordinate uid available" / "no POSIX ACL support" as the
# SKIP reason. Measured on the reference host: /etc/subuid HAS an entry and setfacl works; what fails is the
# namespace root itself -- chown and `setpriv --reuid` get EPERM because kernel.apparmor_restrict_unprivileged_userns=1.
# A SKIP must state the cause it measured (§11.4.6), with the closed §11.4.69 reason code `topology_unsupported`.
#
# Output: `ok` when chown AND setresuid inside the namespace work; otherwise a short cause, e.g.
#   `namespace root gets EPERM (chown: Operation not permitted; setpriv: setresuid failed: Operation not permitted);
#    subuid entry present; kernel.apparmor_restrict_unprivileged_userns=1`
# Exit: 0 always (a probe, never a gate). Creates one temp directory, removed before exit. No credentials touched.
# =============================================================================
set -u
NS=(unshare --map-users=auto --map-groups=auto --map-root-user)
me="$(id -un 2>/dev/null || echo "?")"
if ! command -v unshare >/dev/null 2>&1; then echo "unshare not installed"; exit 0; fi
if ! command -v setpriv >/dev/null 2>&1; then echo "setpriv not installed"; exit 0; fi
sub="subuid entry absent for $me"
grep -q "^$me:" /etc/subuid 2>/dev/null && sub="subuid entry present"
aa="$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)"
[ -n "$aa" ] && aa="; kernel.apparmor_restrict_unprivileged_userns=$aa"
d="$(mktemp -d)" || { echo "mktemp failed"; exit 0; }
: >"${d:?}/p"
c_err="$("${NS[@]}" chown 1000:1000 "${d:?}/p" 2>&1 >/dev/null)"; c_rc=$?
s_err="$("${NS[@]}" setpriv --reuid=1000 --regid=1000 --clear-groups true 2>&1 >/dev/null)"; s_rc=$?
"${NS[@]}" rm -rf "${d:?}" >/dev/null 2>&1
rm -rf "${d:?}"
if [ "$c_rc" = 0 ] && [ "$s_rc" = 0 ]; then echo ok; exit 0; fi
c_err="$(printf '%s' "$c_err" | head -n1 | sed 's/^chown: [^:]*: /chown: /; s/ (os error [0-9]*)//')"
s_err="$(printf '%s' "$s_err" | head -n1)"
[ "$c_rc" = 0 ] && c_err="chown ok"
[ "$s_rc" = 0 ] && s_err="setpriv ok"
echo "namespace root cannot act as another uid (${c_err:-chown rc=$c_rc}; ${s_err:-setpriv rc=$s_rc}); $sub$aa"
