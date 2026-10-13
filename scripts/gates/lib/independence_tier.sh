#!/bin/sh
# =============================================================================
# independence_tier.sh — host-boundary detector + honest tier degradation
#                        (T117, spec 002; FR-033/FR-034)
# =============================================================================
#
# WHAT THIS ANSWERS: "what independence tier was ACHIEVED on THIS host?" — a
# MEASUREMENT. seam_tier_table.sh answers "what tier does this seam REQUIRE?" —
# a POLICY statement. Conflating the two is the exact theatre this feature
# exists to prevent: a seam that REQUIRES capability separation, on a host where
# none EXISTS, must record `instance` and say so. An unfulfilled `capability`
# claim is worse than an honest `instance` one, because a reader who trusts the
# record then believes a boundary is protecting them that is not there.
#
# THE MEASUREMENT (research D-4): a capability boundary exists for a store when
# the store is owned by a uid OTHER than the producer's AND the producer cannot
# write it. On a single-uid host neither half can be arranged by an agent —
# ownership defeats ACLs, the append-only attribute needs privilege the agent
# lacks, and any key the producer can use it can also read. So on such a host
# this detector reports ABSENT, every time, correctly.
#
# THE DETECTOR'S OWN CONTROL NEEDLE (§11.4.201(7)(b)) — load-bearing: a detector
# that is simply BROKEN also reports "no boundary". Those two states are
# indistinguishable from the outside, and reporting the second as the first is a
# false null. So before ANY absence is reported, the SAME code path is run
# against a KNOWN-PRESENT boundary (a root-owned, non-producer-writable path —
# /etc/passwd by default, overridable via ITIER_NEEDLE_PATH). Needle found =>
# an absence is a real absence. Needle NOT found => the detector reports itself
# BLIND (rc 3) and NEVER reports `instance`.
#
# TRIPWIRE (FR-036, observable filesystem state): when CBG_CAPABILITY_TRIPWIRE
# names a path, ENTERING the capability path touches it. Scenario S9 asserts the
# marker is ABSENT after an ordinary seam — an observable state check, not a
# "was the function called" assertion that a refactor can quietly satisfy.
#
# Usage (executed):
#   sh independence_tier.sh detect <store_path>        -> rc 0 present / 1 absent / 3 blind
#   sh independence_tier.sh achieved <seam> <store>    -> prints instance|capability
#   sh independence_tier.sh --selftest
# Usage (sourced):
#   . independence_tier.sh ; itier_detect_boundary <store> ; itier_achieved <seam> <store>
#
# POSIX sh; `sh -n` AND `bash -n` clean; every variable `_itier_`/`ITIER_`
# prefixed (§11.4.67 safe-sourced-lib discipline).
# =============================================================================

ITIER_NEEDLE_PATH=${ITIER_NEEDLE_PATH:-/etc/passwd}

# T048 round-37 independent review (R36-B3): `stat`/`id` were called bare,
# resolved via $PATH -- a PATH-prepended fake `stat` (e.g. `echo 0`) made
# this file's own boundary predicate measure a fabricated owner uid, turning
# a REFUSE (independence_tier_NOT_IN_SET on an unsupported `capability`
# claim) into a false ALLOW; `export -f stat` reproduced the same mask and
# was not caught because these two names were absent from the companion
# closed-set guard in critical_blocker_gate.sh. Hardened via the SAME
# absolute-path primitive every other external command in the sibling gate
# file already uses; `stat`/`id` are additionally added to that gate's
# closed-set guard so the export-f variant is caught there.
if [ -x /usr/bin/stat ]; then _ITIER_BIN_STAT=/usr/bin/stat
elif [ -x /bin/stat ]; then _ITIER_BIN_STAT=/bin/stat
else _ITIER_BIN_STAT=stat
fi
if [ -x /usr/bin/id ]; then _ITIER_BIN_ID=/usr/bin/id
elif [ -x /bin/id ]; then _ITIER_BIN_ID=/bin/id
else _ITIER_BIN_ID=id
fi

_itier_tripwire() {   # record that the capability path was ENTERED
    [ -n "${CBG_CAPABILITY_TRIPWIRE:-}" ] || return 0
    : > "$CBG_CAPABILITY_TRIPWIRE" 2>/dev/null || true
    return 0
}

# --- the raw boundary predicate, applied to ONE path -------------------------
# rc 0 = boundary present, 1 = absent, 2 = path unusable (cannot be measured).
_itier_boundary_raw() {  # <path>
    _itier_p="${1:-}"
    [ -n "$_itier_p" ] || return 2
    [ -e "$_itier_p" ] || return 2
    _itier_owner=$("$_ITIER_BIN_STAT" -c '%u' "$_itier_p" 2>/dev/null) || return 2
    [ -n "$_itier_owner" ] || return 2
    _itier_me=$("$_ITIER_BIN_ID" -u 2>/dev/null) || return 2
    # BOTH halves are required. Owned-by-another-uid but world-writable is not a
    # boundary; owned-by-me but chmod 444 is not one either (I can chmod it back).
    if [ "$_itier_owner" != "$_itier_me" ] && [ ! -w "$_itier_p" ]; then
        return 0
    fi
    return 1
}

# --- the public detector: needle FIRST, then the subject ---------------------
itier_detect_boundary() {  # <store_path> -> rc 0 present / 1 absent / 3 BLIND
    _itier_store="${1:-}"
    _itier_tripwire
    # (1) CONTROL NEEDLE — same function, same host, a boundary known to exist.
    _itier_boundary_raw "$ITIER_NEEDLE_PATH"
    _itier_needle_rc=$?
    if [ "$_itier_needle_rc" -ne 0 ]; then
        printf '[itier] BLIND detector could not see a KNOWN-PRESENT boundary at needle=%s (raw rc=%s, uid=%s) — refusing to report an absence, because a broken detector and a boundary-less host look identical from here (§11.4.201(7)(b))\n' \
            "$ITIER_NEEDLE_PATH" "$_itier_needle_rc" "$("$_ITIER_BIN_ID" -u 2>/dev/null)" >&2
        return 3
    fi
    # (2) the SUBJECT — only now is an absence meaningful.
    _itier_boundary_raw "$_itier_store"
    _itier_sub_rc=$?
    case "$_itier_sub_rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) printf '[itier] BLIND store path not measurable: %s (raw rc=%s)\n' "$_itier_store" "$_itier_sub_rc" >&2
           return 3 ;;
    esac
}

# --- the achieved tier -------------------------------------------------------
# ALWAYS the measured value. The seam's REQUIRED tier is deliberately NOT an
# input here: a requirement cannot conjure a boundary, and letting it do so is
# precisely the claim this file refuses to let anyone make.
itier_achieved() {  # <seam_id> <store_path> -> prints instance|capability ; rc 0/3
    _itier_seam="${1:-}"
    _itier_st="${2:-}"
    itier_detect_boundary "$_itier_st"
    _itier_rc=$?
    case "$_itier_rc" in
        0) printf 'capability\n'; return 0 ;;
        1) printf 'instance\n';   return 0 ;;
        *) printf 'blind\n';      return 3 ;;
    esac
}

# --- may a row CLAIM `capability`? ------------------------------------------
# rc 0 = the claim is supported by a measured boundary; 1 = it is NOT (refuse);
# 3 = the detector is blind, so the claim cannot be adjudicated (refuse, and say
# which of the two it is — one sends an operator to fix a host, the other to fix
# an instrument, and calling one the other is a false accusation).
itier_claim_supported() {  # <claimed_tier> <store_path>
    _itier_claim="${1:-}"
    _itier_cst="${2:-}"
    case "$_itier_claim" in
        capability) : ;;
        *) return 0 ;;   # only `capability` needs a host boundary behind it
    esac
    itier_detect_boundary "$_itier_cst"
    return $?
}

# --- self-check (§11.4.107(10)) ---------------------------------------------
_itier_selftest() {
    _itier_trc=0
    _it_ok()  { printf '  PASS %s\n' "$1"; }
    _it_bad() { printf '  FAIL %s\n' "$1" >&2; _itier_trc=1; }
    _itier_tmp=$(mktemp -d) || return 2

    # (N) NEEDLE: the detector CAN see a real, known-present boundary.
    _itier_boundary_raw "$ITIER_NEEDLE_PATH"
    if [ $? -eq 0 ]; then _it_ok "NEEDLE detector sees the known-present boundary at $ITIER_NEEDLE_PATH"
    else _it_bad "NEEDLE detector CANNOT see the known-present boundary at $ITIER_NEEDLE_PATH — every absence below would be a false null"; fi

    # (1) a self-owned, self-writable store => boundary ABSENT (the real case here)
    : > "$_itier_tmp/store.jsonl"
    itier_detect_boundary "$_itier_tmp/store.jsonl"
    _itier_r=$?
    if [ "$_itier_r" -eq 1 ]; then _it_ok "self-owned writable store => boundary ABSENT (rc=1)"
    else _it_bad "self-owned writable store => rc=$_itier_r (expected 1 ABSENT)"; fi

    # (1b) DECOY — the false-positive guard for the OWNERSHIP half of the
    #      predicate. A path owned by ANOTHER uid but still WRITABLE by me is
    #      NOT a boundary: I can still rewrite the store, which is the entire
    #      thing a boundary would prevent.
    #      This case is load-bearing and was added after measurement, not from
    #      theory: dropping the `[ ! -w ]` half of _itier_boundary_raw passed
    #      EVERY other assertion in this selftest (8/8 PASS, rc=0 on knowingly
    #      broken code), because no fixture here was other-uid-owned AND
    #      self-writable. Without this case the ownership check alone is
    #      decoration for that dimension (§11.4.201/§11.4.107(10): a golden-FALSE
    #      set must contain a decoy the mutation actually defeats).
    _itier_decoy=''
    _itier_uid=$("$_ITIER_BIN_ID" -u 2>/dev/null)
    for _itier_c in /tmp /var/tmp /dev/shm; do
        [ -d "$_itier_c" ] || continue
        _itier_co=$("$_ITIER_BIN_STAT" -c '%u' "$_itier_c" 2>/dev/null) || continue
        [ -n "$_itier_co" ] || continue
        if [ "$_itier_co" != "$_itier_uid" ] && [ -w "$_itier_c" ]; then
            _itier_decoy="$_itier_c"; break
        fi
    done
    if [ -n "$_itier_decoy" ]; then
        itier_detect_boundary "$_itier_decoy" >/dev/null 2>&1
        _itier_dr=$?
        if [ "$_itier_dr" -eq 1 ]; then
            _it_ok "DECOY other-uid-owned but SELF-WRITABLE ($_itier_decoy) => ABSENT (rc=1); ownership alone is NOT accepted as a boundary"
        else
            _it_bad "DECOY other-uid-owned but self-writable ($_itier_decoy) => rc=$_itier_dr (expected 1 ABSENT) — the writability half of the predicate is not being applied, so any other-uid store would be miscounted as a capability boundary"
        fi
    else
        printf '  SKIP no other-uid-owned self-writable path found among /tmp /var/tmp /dev/shm — the ownership-half decoy cannot be constructed on this host, so that dimension is NOT covered here (§11.4.3 skip-with-reason, never a pass)\n'
    fi

    # (1c) OWNERSHIP-DECOY — the false-positive guard for the OTHER half of the
    #      predicate: the OWNERSHIP check. A path owned by ME but made read-only
    #      (chmod 444) is NOT a boundary — I own it, so I can chmod it back and
    #      rewrite the store at will, which is the entire thing a boundary would
    #      prevent (this file's own predicate comment states exactly that case).
    #      This case is load-bearing and was added after measurement, not from
    #      theory: dropping the `[ "$_itier_owner" != "$_itier_me" ]` half of
    #      _itier_boundary_raw passed EVERY other assertion in this selftest
    #      (9/9 PASS, rc=0 on knowingly broken code), because no fixture here was
    #      self-owned AND non-writable. Without this case the writability check
    #      alone is decoration for that dimension, and the detector OVERCLAIMS
    #      the achieved tier (§11.4.201/§11.4.107(10): a golden-FALSE set must
    #      contain a decoy the mutation actually defeats).
    #      KILL-POWER PRECONDITION (§11.4.201(7)(b)-shaped): this fixture only
    #      separates the two predicates while `[ ! -w ]` is genuinely TRUE for
    #      this uid. uid 0 bypasses the permission bits entirely, and some
    #      filesystems/ACLs do not honour them, so the precondition is MEASURED
    #      and the case SKIPs honestly rather than passing for the wrong reason
    #      (§11.4.3 skip-with-reason, never a pass).
    _itier_ro_dir="$_itier_tmp/ro_fixture"
    (
        # Subshell-scoped cleanup: an EXIT trap installed HERE fires on every
        # exit path of this fixture and can never clobber a caller's EXIT trap
        # when this file is SOURCED (§11.4.14 cleanup, without the sourced-
        # library global-trap hazard that §11.4.67(6) names for `exec`).
        trap 'chmod 0700 "$_itier_ro_dir" 2>/dev/null; rm -rf "$_itier_ro_dir"' EXIT
        mkdir -p "$_itier_ro_dir" 2>/dev/null || exit 3
        : > "$_itier_ro_dir/store.jsonl" 2>/dev/null || exit 3
        chmod 0444 "$_itier_ro_dir/store.jsonl" 2>/dev/null || exit 3
        # Precondition probe: is it REALLY non-writable for this uid?
        if [ -w "$_itier_ro_dir/store.jsonl" ]; then exit 2; fi
        _itier_boundary_raw "$_itier_ro_dir/store.jsonl"
        _itier_ro_rc=$?
        if [ "$_itier_ro_rc" -ne 0 ]; then exit 0; fi
        exit 1
    )
    _itier_ro_v=$?
    case "$_itier_ro_v" in
        0) _it_ok "OWNERSHIP-DECOY self-owned but NON-WRITABLE (chmod 444) => ABSENT; non-writability alone is NOT accepted as a boundary" ;;
        1) _it_bad "OWNERSHIP-DECOY self-owned chmod-444 path was reported as a BOUNDARY — the ownership half of the predicate is not being applied, so any self-owned read-only store would be miscounted as a capability boundary (the detector OVERCLAIMS the achieved tier)" ;;
        2) printf '  SKIP OWNERSHIP-DECOY this uid can write a chmod-444 file it owns (uid 0, or a filesystem/ACL not honouring the mode bits), so the ownership-half decoy cannot be constructed here and that dimension is NOT covered (§11.4.3 skip-with-reason, never a pass)\n' ;;
        *) _it_bad "OWNERSHIP-DECOY fixture setup failed (mkdir/create/chmod under $_itier_tmp) — the ownership dimension was NOT exercised" ;;
    esac

    # (1d) SUBJECT-UNMEASURABLE — the false-null guard for M9 (the OTHER
    #      `return 3` site). itier_detect_boundary has TWO independent
    #      `return 3` sites: the NEEDLE-unreachable branch (exercised by the
    #      BLIND fixture below) and the SUBJECT-unmeasurable branch (this
    #      fixture) — a store path that does not exist, so
    #      _itier_boundary_raw cannot even stat it (raw rc=2). Those are TWO
    #      DIFFERENT lines in TWO different `case` arms; killing one proves
    #      NOTHING about the other. A mutation of the SUBJECT arm alone
    #      (leaving the NEEDLE arm untouched) passed EVERY other assertion in
    #      this selftest (10/10 PASS, rc=0 on knowingly broken code) —
    #      CONDUCTOR-CONFIRMED 2026-08-22 — because no fixture here drove an
    #      unmeasurable SUBJECT while the NEEDLE stayed reachable. Without
    #      this case, "cannot be measured" silently degrades into "there is NO
    #      boundary" — the EXACT false null this file's own header (see the
    #      "THE DETECTOR'S OWN CONTROL NEEDLE" block above) exists to prevent,
    #      and the detector OVERCLAIMS `instance` for a store it never
    #      actually looked at (§11.4.201(6) false-null; §11.4.201/§11.4.107(10):
    #      a golden-FALSE set must contain a decoy the mutation actually
    #      defeats).
    #      KILL-POWER PRECONDITION (§11.4.201(7)(b)-shaped): this fixture only
    #      separates the two `return 3` sites while the NEEDLE is genuinely
    #      reachable right now AND the candidate SUBJECT path genuinely does
    #      not exist. Both are MEASURED, and the case SKIPs honestly rather
    #      than passing for the wrong reason (§11.4.3 skip-with-reason, never
    #      a pass).
    (
        # Subshell-scoped cleanup — see the (1c) comment above for why the
        # trap lives here rather than at file/sourced-library scope
        # (§11.4.67(6)).
        _itier_su_path="$_itier_tmp/subject-unmeasurable-$$"
        trap 'rm -f "$_itier_su_path" 2>/dev/null' EXIT
        # Precondition 1: the needle is genuinely reachable right now.
        _itier_boundary_raw "$ITIER_NEEDLE_PATH"
        if [ $? -ne 0 ]; then exit 2; fi
        # Precondition 2: the candidate subject path genuinely does not exist
        # (so _itier_boundary_raw's own `[ -e "$_itier_p" ]` check is what
        # makes it unmeasurable, not a fixture bug).
        if [ -e "$_itier_su_path" ]; then exit 2; fi
        itier_detect_boundary "$_itier_su_path" >/dev/null 2>&1
        _itier_su_rc=$?
        case "$_itier_su_rc" in
            3) exit 0 ;;
            1) exit 1 ;;
            *) exit 4 ;;
        esac
    )
    _itier_su_v=$?
    case "$_itier_su_v" in
        0) _it_ok "SUBJECT-UNMEASURABLE nonexistent (unmeasurable) subject + reachable needle => BLIND (rc=3), never a reported ABSENT" ;;
        1) _it_bad "SUBJECT-UNMEASURABLE nonexistent (unmeasurable) subject + reachable needle reported ABSENT (rc=1) instead of BLIND — the SUBJECT's own 'return 3' degraded into an overclaimed absence; a store the detector could not even see was reported as having NO boundary (the exact false null FR-033/§11.4.201(6) forbids)" ;;
        2) printf '  SKIP SUBJECT-UNMEASURABLE precondition unmet (needle unreachable, or the candidate subject path unexpectedly already exists) — this dimension is NOT covered here (§11.4.3 skip-with-reason, never a pass)\n' ;;
        *) _it_bad "SUBJECT-UNMEASURABLE fixture returned an unexpected rc from itier_detect_boundary (neither 1 ABSENT nor 3 BLIND) — the subject dimension was NOT exercised as designed" ;;
    esac

    # (2) achieved tier for that store is `instance`, NOT capability
    _itier_t=$(itier_achieved qa-deploy "$_itier_tmp/store.jsonl")
    if [ "$_itier_t" = "instance" ]; then _it_ok "achieved tier on a single-uid host is 'instance' (honest degradation)"
    else _it_bad "achieved tier reported '$_itier_t' (expected instance)"; fi

    # (3) a CLAIM of capability against that store is NOT supported
    itier_claim_supported capability "$_itier_tmp/store.jsonl"
    if [ $? -ne 0 ]; then _it_ok "a 'capability' claim with no measured boundary is NOT supported (refusable)"
    else _it_bad "a 'capability' claim was reported SUPPORTED with no boundary — the exact theatre FR-033 forbids"; fi

    # (4) NEGATIVE CONTROL — the false-positive guard. A claim of `instance` is
    #     NOT refused, and the detector reports PRESENT for a genuine boundary.
    itier_claim_supported instance "$_itier_tmp/store.jsonl"
    if [ $? -eq 0 ]; then _it_ok "NEGATIVE CONTROL an 'instance' claim needs no boundary and is NOT refused"
    else _it_bad "an 'instance' claim was refused — false-positive refusal (§11.4.201(1))"; fi

    itier_detect_boundary "$ITIER_NEEDLE_PATH"
    if [ $? -eq 0 ]; then _it_ok "NEGATIVE CONTROL a genuine boundary store reports PRESENT (rc=0), so PRESENT is reachable"
    else _it_bad "a genuine boundary reported NOT-present — the detector can only ever say 'absent', which proves nothing"; fi

    # (5) BLIND path: an unreachable needle makes the detector report BLIND (3),
    #     never `instance`. This is the check that keeps a broken detector from
    #     masquerading as a boundary-less host.
    ( ITIER_NEEDLE_PATH="$_itier_tmp/no-such-needle"; itier_detect_boundary "$_itier_tmp/store.jsonl" ) 2>/dev/null
    if [ $? -eq 3 ]; then _it_ok "BLIND an unreachable needle yields rc=3 BLIND, never a reported absence"
    else _it_bad "an unreachable needle did NOT yield BLIND — a broken detector would report 'instance'"; fi

    # (6) TRIPWIRE observable: entering the capability path touches the marker.
    ( CBG_CAPABILITY_TRIPWIRE="$_itier_tmp/tw"; export CBG_CAPABILITY_TRIPWIRE
      itier_detect_boundary "$_itier_tmp/store.jsonl" >/dev/null 2>&1 )
    if [ -e "$_itier_tmp/tw" ]; then _it_ok "TRIPWIRE entering the capability path leaves an observable marker"
    else _it_bad "TRIPWIRE marker absent after entering the capability path — S9's absence assertion would prove nothing"; fi

    rm -rf "$_itier_tmp"
    if [ "$_itier_trc" -eq 0 ]; then
        printf 'INDEPENDENCE-TIER SELFTEST PASS — needle-guarded detector (cannot report a blind instrument as an absence), honest degradation to instance on a single-uid host, an unsupported capability CLAIM is refusable, and both PRESENT and ABSENT are reachable (so neither verdict is hardcoded)\n'
    else
        printf 'INDEPENDENCE-TIER SELFTEST FAIL\n' >&2
    fi
    return "$_itier_trc"
}

# --- dispatch (content-identified, never by filename) ------------------------
_ITIER_SELF_SENTINEL='itier-self-id-9c3d72fb-independence-tier'
_itier_is_self() { [ -n "${1:-}" ] && [ -r "$1" ] && grep -qF "$_ITIER_SELF_SENTINEL" "$1" 2>/dev/null; }

if [ -n "${BASH_SOURCE:-}" ]; then
    if [ "${BASH_SOURCE}" = "$0" ]; then _ITIER_EXECUTED=1; else _ITIER_EXECUTED=0; fi
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
    case "$ZSH_EVAL_CONTEXT" in *:file*) _ITIER_EXECUTED=0 ;; *) _ITIER_EXECUTED=1 ;; esac
elif _itier_is_self "$0"; then _ITIER_EXECUTED=1
elif [ -r "$0" ]; then _ITIER_EXECUTED=0
else _ITIER_EXECUTED=u
fi

if [ "$_ITIER_EXECUTED" = "1" ]; then
    case "${1:-}" in
        detect)     itier_detect_boundary "${2:-}"; exit $? ;;
        achieved)   itier_achieved "${2:-}" "${3:-}"; exit $? ;;
        --selftest) _itier_selftest; exit $? ;;
        *) printf 'usage: %s detect <store> | achieved <seam> <store> | --selftest\n' "$0" >&2; exit 2 ;;
    esac
fi
