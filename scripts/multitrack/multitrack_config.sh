#!/usr/bin/env bash
# =============================================================================
# multitrack_config.sh — per-host multi-track drive config loader + detection
#                         + protect-guard library (§11.4.167 / §11.4.111 /
#                         §11.4.10 / §11.4.133).
# -----------------------------------------------------------------------------
# Purpose:
#   Sourceable POSIX-sh library that (a) resolves the current host, (b) loads
#   its per-host YAML drive<->track map (config/multitrack/<hostname>.yaml),
#   (c) detects LIVE drives at runtime matched by STABLE SERIAL (never by
#   /dev/nvmeXn1 enumeration index — §11.4.111), (d) exposes a HARD
#   protect-guard that refuses any drive whose serial is protected OR whose
#   parent disk carries a /, /boot, or /home mountpoint (belt-and-suspenders),
#   and (e) computes the dynamic track->drive->mount plan (1 drive = system
#   only; 2 = system + 1 track; N = system + N-1 tracks, in `tracks` order).
#
# Usage (sourced):
#   . scripts/multitrack/multitrack_config.sh
#   MT_HOST=$(mt_resolve_host)
#   cfg=$(mt_config_file "$MT_HOST") || { echo "no config for $MT_HOST"; exit 1; }
#   mt_load_config "$cfg"          # sets MT_* variables in the caller shell
#   mt_detect_drives               # prints  SERIAL|DEV|MOUNTS|HASCHILD  lines
#   mt_plan                        # prints  TRACK ...  +  TRACKS_READY=<n>
#   mt_protect_guard "$dev" "$serial" "$mounts"  # 0 = SAFE, 1 = PROTECTED
#   mt_config_conductor "$cfg"     # prints the `conductor:` alias (§11.4.177), empty if unset
#   mt_config_fallback_signatures "$cfg"  # prints `fallback.signatures:` list, one per line
#
# Inputs:
#   config/multitrack/<hostname>.yaml    (schema_version: 1)
#   Env override MT_CONFIG_DIR           (default: <repo>/config/multitrack)
#   Env override MT_FIXTURE_DRIVES       (newline list of SERIAL|DEV|MOUNTS|HASCHILD
#                                         lines; when set, replaces live lsblk —
#                                         the deterministic test seam, no root/hw)
#
# Outputs:
#   MT_HOSTNAME MT_MACHINE_ID MT_PROTECTED_SERIALS MT_TRACK_COUNT
#   MT_TRACK_<i>_ID/_SERIAL/_MOUNT/_ROLE/_FS  (i = 1..MT_TRACK_COUNT)
#
# Side-effects:  NONE. Every function here is read-only. All destructive work
#   lives in multitrack_drive_prep.sh behind --apply + root + confirm.
#
# Dependencies:  awk, lsblk (real mode only), hostname OR /etc/machine-id.
#
# Cross-references:
#   docs/scripts/multitrack_drive_prep.md
#   docs/guides/MULTITRACK_DRIVE_PREP.md  (§ user guide)
#   config/multitrack/<host>.yaml    (seeded per-host map)
#   §11.4.111 resolve-by-stable-name-not-index · §11.4.10 credentials ·
#   §11.4.133 target/hardware safety · §11.4.167 feature work-stream lifecycle
# =============================================================================

# --- repo root resolution (works whether sourced from repo root or elsewhere) -
mt__self_dir() {
    # POSIX-ish dirname of this sourced file
    d=${MT_SELF:-$0}
    case "$d" in
        */*) printf '%s\n' "${d%/*}" ;;
        *)   printf '%s\n' "." ;;
    esac
}

mt_repo_root() {
    # (a) operator-pinned root always wins (e.g. a consumer shim / a test seam).
    if [ -n "${MT_REPO_ROOT:-}" ]; then
        printf '%s\n' "$MT_REPO_ROOT"
        return 0
    fi
    # scripts/multitrack/ -> ../.. == this checkout's top dir.
    sd=$(mt__self_dir)
    _mtrr_base=$( cd "$sd/../.." 2>/dev/null && pwd ) || _mtrr_base=""
    # (b) standalone-in-own-repo: the CONSUMER config lives DIRECTLY under base.
    if [ -n "$_mtrr_base" ] && [ -d "$_mtrr_base/config/multitrack" ]; then
        printf '%s\n' "$_mtrr_base"
        return 0
    fi
    # (c) embedded-as-a-submodule (§11.4.35): base is the SUBMODULE root; the
    #     CONSUMER project root is git's superproject working tree. Adopt it IFF
    #     it carries config/multitrack (project-agnostic — NO project string,
    #     §11.4.111 resolve-by-stable-name). git absent / not-a-submodule => sp
    #     empty (stderr suppressed) => fall through to (d) unchanged.
    if [ -n "$_mtrr_base" ] && command -v git >/dev/null 2>&1; then
        _mtrr_sp=$( git -C "$_mtrr_base" rev-parse --show-superproject-working-tree 2>/dev/null ) || _mtrr_sp=""
        if [ -n "$_mtrr_sp" ] && [ -d "$_mtrr_sp/config/multitrack" ]; then
            printf '%s\n' "$_mtrr_sp"
            return 0
        fi
    fi
    # (c2) config-less consumer (§11.4.187 default single-track mode): the engine
    #     is embedded as a submodule but the consumer has NOT authored a
    #     config/multitrack dir yet. Branch (c) could not fire (it REQUIRES that
    #     dir), and branch (d) would return the SUBMODULE root — which is the
    #     wrong project entirely. The superproject working tree IS the consumer
    #     root, so adopt it. Guarded to fire ONLY when base carries no
    #     config/multitrack, so every already-configured consumer is untouched.
    if [ -n "$_mtrr_base" ] && [ ! -d "$_mtrr_base/config/multitrack" ] \
       && command -v git >/dev/null 2>&1; then
        _mtrr_sp2=$( git -C "$_mtrr_base" rev-parse --show-superproject-working-tree 2>/dev/null ) || _mtrr_sp2=""
        if [ -n "$_mtrr_sp2" ] && [ -d "$_mtrr_sp2" ]; then
            printf '%s\n' "$_mtrr_sp2"
            return 0
        fi
    fi
    # (d) last resort: base (unchanged legacy behaviour; empty only if cd failed).
    printf '%s\n' "$_mtrr_base"
}

mt_config_dir() {
    if [ -n "${MT_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$MT_CONFIG_DIR"
    else
        printf '%s/config/multitrack\n' "$(mt_repo_root)"
    fi
}

# --- host resolution: hostname first, /etc/machine-id as disambiguator --------
mt_resolve_host() {
    h=""
    if command -v hostname >/dev/null 2>&1; then
        h=$(hostname 2>/dev/null | cut -d. -f1)
    fi
    if [ -z "$h" ] && [ -r /etc/hostname ]; then
        h=$(cut -d. -f1 < /etc/hostname 2>/dev/null)
    fi
    if [ -z "$h" ]; then
        # last resort: machine-id (config filename may be machine-id-keyed)
        [ -r /etc/machine-id ] && h=$(cut -c1-16 < /etc/machine-id)
    fi
    printf '%s\n' "$h"
}

# --- config file path (error clearly if the host has no config) ---------------
mt_config_file() {
    host=${1:-$(mt_resolve_host)}
    dir=$(mt_config_dir)
    f="$dir/$host.yaml"
    if [ -r "$f" ]; then
        printf '%s\n' "$f"
        return 0
    fi
    # machine-id fallback filename
    if [ -r /etc/machine-id ]; then
        mid=$(cut -c1-16 < /etc/machine-id)
        f2="$dir/$mid.yaml"
        if [ -r "$f2" ]; then
            printf '%s\n' "$f2"
            return 0
        fi
    fi
    printf 'mt_config_file: no per-host config for host=%s in %s (looked for %s)\n' \
        "$host" "$dir" "$f" >&2
    return 1
}

# --- YAML -> shell assignments (focused parser for schema_version: 1) ---------
# Emits eval-able MT_* lines. Section-gated so device_pool `- id:` / `adb_serial:`
# never leak into the tracks list.
mt__parse_awk() {
    awk '
    function strip(v){
        sub(/[ \t]*#.*$/,"",v)            # drop inline comment
        gsub(/^[ \t]+|[ \t]+$/,"",v)      # trim
        gsub(/^"|"$/,"",v)                # drop surrounding double quotes
        return v
    }
    BEGIN{ section=""; tc=0; prot="" }
    {
        line=$0
        # blank / pure-comment line
        t=line; sub(/^[ \t]*/,"",t)
        if (t=="" || t ~ /^#/) next
        # indent of first non-space
        m=match(line,/[^ ]/); indent=(m>0)?m-1:0
        # top-level key toggles the active section
        if (indent==0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            ci=index(line,":"); section=substr(line,1,ci-1); next
        }
        # left-trim, detect "- " list-item prefix
        lt=line; sub(/^[ \t]+/,"",lt)
        isitem=0
        if (lt ~ /^- /) { sub(/^- /,"",lt); isitem=1 }
        ci=index(lt,":"); if (ci==0) next
        k=substr(lt,1,ci-1); gsub(/[ \t]/,"",k)
        v=strip(substr(lt,ci+1))
        if (section=="host") {
            if (k=="hostname")   printf "MT_HOSTNAME=%c%s%c\n", 39, v, 39
            if (k=="machine_id") printf "MT_MACHINE_ID=%c%s%c\n", 39, v, 39
        } else if (section=="protected_drives") {
            if (isitem && k=="serial") prot=(prot==""?v:prot" "v)
        } else if (section=="tracks") {
            if (isitem && k=="id") {
                tc++
                printf "MT_TRACK_%d_ID=%c%s%c\n", tc, 39, v, 39
            } else if (tc>0) {
                if (k=="drive_serial") printf "MT_TRACK_%d_SERIAL=%c%s%c\n", tc, 39, v, 39
                if (k=="mount")        printf "MT_TRACK_%d_MOUNT=%c%s%c\n", tc, 39, v, 39
                if (k=="role")         printf "MT_TRACK_%d_ROLE=%c%s%c\n", tc, 39, v, 39
                if (k=="fs")           printf "MT_TRACK_%d_FS=%c%s%c\n", tc, 39, v, 39
                if (k=="branch")         printf "MT_TRACK_%d_BRANCH=%c%s%c\n", tc, 39, v, 39
                if (k=="branch_pattern") printf "MT_TRACK_%d_BRANCH=%c%s%c\n", tc, 39, v, 39
            }
        }
        # host/protected/tracks only; device_pool + lease_policy ignored
    }
    END{
        printf "MT_PROTECTED_SERIALS=%c%s%c\n", 39, prot, 39
        printf "MT_TRACK_COUNT=%c%d%c\n", 39, tc, 39
    }
    ' "$1"
}

mt_load_config() {
    cfg=$1
    [ -r "$cfg" ] || { echo "mt_load_config: unreadable $cfg" >&2; return 1; }
    # clear any prior track vars so a re-load never leaves stale indices
    i=1
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        unset "MT_TRACK_${i}_ID" "MT_TRACK_${i}_SERIAL" "MT_TRACK_${i}_MOUNT" \
              "MT_TRACK_${i}_ROLE" "MT_TRACK_${i}_FS" "MT_TRACK_${i}_BRANCH" 2>/dev/null || true
        i=$((i + 1))
    done
    MT_HOSTNAME=""; MT_MACHINE_ID=""; MT_PROTECTED_SERIALS=""; MT_TRACK_COUNT=0
    eval "$(mt__parse_awk "$cfg")"
    export MT_HOSTNAME MT_MACHINE_ID MT_PROTECTED_SERIALS MT_TRACK_COUNT
    return 0
}

# =============================================================================
# UNIVERSAL DEFAULT SINGLE-TRACK MODE (§11.4.187 / §11.4.177 / §11.4.6 /
# §11.4.201)
# -----------------------------------------------------------------------------
# WHY: the engine previously FATALED on any host with no per-host config file,
# so multi-track was non-universal — it worked ONLY on a hand-provisioned host.
# The refusal was RIGHT about never inventing HOST DATA (mount paths, drive
# serials, alias->track maps cannot be guessed, §11.4.6). But "Track 1 is the
# project root you are standing in" is NOT invented data: it is a DEFINED
# DEFAULT, derivable with certainty from the invocation context (§11.4.177
# invocation-directory operation). Fataling when a correct and safe default
# exists is the §11.4.201 FALSE-REFUSAL class.
#
# The split this introduces (the ONLY behaviour change):
#   * a host config EXISTS      -> load it exactly as before (no change at all)
#   * a host config is MALFORMED-> still FATAL (that IS ambiguity, never defaulted)
#   * NO host config at all     -> DEFAULT to ONE track, track-1 = project root,
#                                  and SAY SO LOUDLY on stderr so a defaulted
#                                  setup can never be mistaken for a provisioned
#                                  multi-track host (§11.4.6 honesty).
# =============================================================================

# --- resolve the invocation project root (the default Track 1) ---------------
# Deterministic, never guessed, never a hardcoded project path (§11.4.177).
# Order: (a) an explicit caller/operator pin, (b) the git SUPERPROJECT of the
# invocation dir (engine embedded as a submodule -> the CONSUMER root), (c) the
# git toplevel of the invocation dir, (d) the invocation dir itself.
# Returns non-zero (prints NOTHING) when none resolves to a real directory —
# the caller MUST then fail loudly rather than default to a wrong root.
mt_default_project_root() {
    if [ -n "${MT_REPO_ROOT:-}" ] && [ -d "${MT_REPO_ROOT}" ]; then
        printf '%s\n' "$MT_REPO_ROOT"
        return 0
    fi
    _mtd_base=${MT_DEFAULT_ROOT_FROM:-$PWD}
    if [ -d "$_mtd_base" ] && command -v git >/dev/null 2>&1; then
        _mtd_sp=$( git -C "$_mtd_base" rev-parse --show-superproject-working-tree 2>/dev/null ) || _mtd_sp=""
        if [ -n "$_mtd_sp" ] && [ -d "$_mtd_sp" ]; then
            printf '%s\n' "$_mtd_sp"
            return 0
        fi
        _mtd_tl=$( git -C "$_mtd_base" rev-parse --show-toplevel 2>/dev/null ) || _mtd_tl=""
        if [ -n "$_mtd_tl" ] && [ -d "$_mtd_tl" ]; then
            printf '%s\n' "$_mtd_tl"
            return 0
        fi
    fi
    if [ -d "$_mtd_base" ]; then
        printf '%s\n' "$_mtd_base"
        return 0
    fi
    return 1
}

# --- load the DEFAULT single-track config (no file involved) ------------------
# Sets exactly the same MT_* contract mt_load_config sets, so every downstream
# consumer (mt_plan, the resolver, the orchestrator) is unchanged.
#
# Track-1's MOUNT is the project root's PARENT and the worktree-subdir is the
# project root's BASENAME, so the engine's existing "<mount>/<worktree_subdir>"
# composition yields the project root ITSELF as track-1's worktree — no special
# case anywhere downstream.
#
# Honest emptiness (§11.4.6): MT_MACHINE_ID / MT_PROTECTED_SERIALS / the track's
# drive serial + fs are EMPTY because they are genuinely unknown for a defaulted
# host — never fabricated. A serial-less track is a plain directory, not a drive.
mt_load_default_config() {
    _mtd_root=$(mt_default_project_root) || {
        echo "mt_load_default_config: FATAL — cannot resolve the invocation project root;" >&2
        echo "  refusing to default Track 1 to an unknown location (§11.4.6 no-guessing)." >&2
        echo "  Pin it explicitly with MT_REPO_ROOT=/path/to/project, or author a per-host config." >&2
        return 1
    }
    case "$_mtd_root" in
        /*) : ;;
        *)  echo "mt_load_default_config: FATAL — resolved project root '$_mtd_root' is not an absolute path" >&2
            return 1 ;;
    esac
    i=1
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        unset "MT_TRACK_${i}_ID" "MT_TRACK_${i}_SERIAL" "MT_TRACK_${i}_MOUNT" \
              "MT_TRACK_${i}_ROLE" "MT_TRACK_${i}_FS" "MT_TRACK_${i}_BRANCH" 2>/dev/null || true
        i=$((i + 1))
    done
    MT_HOSTNAME=$(mt_resolve_host)
    MT_MACHINE_ID=""
    MT_PROTECTED_SERIALS=""
    MT_TRACK_COUNT=1
    MT_TRACK_1_ID="track-1"
    MT_TRACK_1_ROLE="main"
    MT_TRACK_1_SERIAL=""
    MT_TRACK_1_FS=""
    MT_TRACK_1_BRANCH=""
    MT_TRACK_1_MOUNT=$(dirname "$_mtd_root")
    MT_DEFAULT_MODE=1
    MT_DEFAULT_TRACK1_ROOT="$_mtd_root"
    MT_WORKTREE_SUBDIR=${MT_WORKTREE_SUBDIR:-$(basename "$_mtd_root")}
    export MT_HOSTNAME MT_MACHINE_ID MT_PROTECTED_SERIALS MT_TRACK_COUNT \
           MT_TRACK_1_ID MT_TRACK_1_ROLE MT_TRACK_1_SERIAL MT_TRACK_1_FS \
           MT_TRACK_1_BRANCH MT_TRACK_1_MOUNT MT_DEFAULT_MODE \
           MT_DEFAULT_TRACK1_ROOT MT_WORKTREE_SUBDIR
    return 0
}

# --- the loud, unmistakable default-mode notice ------------------------------
# Printed to STDERR on EVERY default-mode activation. A defaulted setup must
# never be silently mistaken for a provisioned multi-track host (§11.4.6).
mt_default_mode_notice() {
    _mtd_host=${1:-$(mt_resolve_host)}
    _mtd_dir=${2:-$(mt_config_dir)}
    {
        echo "=============================================================="
        echo "NOTICE: multitrack is running in DEFAULT SINGLE-TRACK MODE."
        echo "        This host has NO per-host config — this is the DEFAULT,"
        echo "        NOT a provisioned multi-track host."
        echo "  host          : $_mtd_host"
        echo "  looked for    : $_mtd_dir/$_mtd_host.yaml   (absent)"
        echo "  tracks        : 1 (default)"
        echo "  track-1 root  : ${MT_DEFAULT_TRACK1_ROOT:-<unresolved>}  (the invocation project root)"
        echo "  To define tracks explicitly (more than one, or a different"
        echo "  Track 1 such as /mnt/track-1), author:"
        echo "        $_mtd_dir/$_mtd_host.yaml"
        echo "  See constitution/scripts/multitrack/README.md - 'Default"
        echo "  single-track mode'."
        echo "=============================================================="
    } >&2
}

# --- THE resolver every caller should use ------------------------------------
# Resolves AND loads the per-host config, falling back to the universal default
# single-track mode when (and ONLY when) no config file exists at all.
#
# Return codes (deliberately distinct so callers can react precisely):
#   0  loaded (either a real config, or the default single-track mode —
#      MT_DEFAULT_MODE=1 distinguishes them)
#   1  no config AND the default could not be established (project root
#      unresolvable), OR strict mode requested via MT_REQUIRE_HOST_CONFIG=1
#      and no config exists
#   3  a config file EXISTS but is unparsable or defines zero tracks — ALWAYS
#      fatal, NEVER defaulted past (that IS ambiguity, §11.4.6)
#
# Sets MT_CFG_FILE to the loaded file path, or the empty string in default mode.
mt_resolve_and_load() {
    _mtr_host=${MT_HOST:-$(mt_resolve_host)}
    if [ -n "${MT_CONFIG:-}" ]; then
        _mtr_cfg=$MT_CONFIG
        if [ ! -r "$_mtr_cfg" ]; then
            echo "mt_resolve_and_load: MT_CONFIG='$_mtr_cfg' is not readable" >&2
            return 3
        fi
    else
        _mtr_cfg=$(mt_config_file "$_mtr_host" 2>/dev/null) || _mtr_cfg=""
    fi

    if [ -n "$_mtr_cfg" ]; then
        # A config EXISTS -> behave exactly as before. Malformed is FATAL.
        if ! mt_load_config "$_mtr_cfg"; then
            echo "mt_resolve_and_load: FATAL — could not parse $_mtr_cfg" >&2
            return 3
        fi
        if [ "${MT_TRACK_COUNT:-0}" -lt 1 ]; then
            echo "mt_resolve_and_load: FATAL — $_mtr_cfg parsed but defines ZERO tracks" >&2
            echo "  A malformed/empty config is NEVER defaulted past (§11.4.6): fix the file," >&2
            echo "  or remove it to fall back to default single-track mode." >&2
            return 3
        fi
        MT_CFG_FILE=$_mtr_cfg
        MT_DEFAULT_MODE=0
        export MT_CFG_FILE MT_DEFAULT_MODE
        return 0
    fi

    # No config at all.
    if [ "${MT_REQUIRE_HOST_CONFIG:-0}" = "1" ]; then
        echo "mt_resolve_and_load: no per-host config for host='$_mtr_host' in $(mt_config_dir)" >&2
        echo "  and MT_REQUIRE_HOST_CONFIG=1 was requested (strict mode: no default)." >&2
        return 1
    fi
    mt_load_default_config || return 1
    MT_CFG_FILE=""
    export MT_CFG_FILE
    mt_default_mode_notice "$_mtr_host"
    return 0
}

# --- device_pool + lease_policy parser (REM-02 device-lock; §11.4.119) ---------
# ADDITIVE + independent of mt__parse_awk: mt_load_config's output is unchanged
# (REM-08 loader untouched). Emits MT_DEVICE_COUNT + MT_DEVICE_<i>_ID/_ADB/
# _MODEL/_CAPS and MT_LEASE_<key>. Inline YAML flow-lists ["a","b"] are split to
# space-joined tokens. Section-gated so tracks/protected never leak in.
mt__parse_pool_awk() {
    awk '
    function strip(v){
        sub(/[ \t]*#.*$/,"",v)
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        gsub(/^"|"$/,"",v)
        return v
    }
    function flowlist(v,   n,arr,i,out,tok){
        gsub(/^\[|\]$/,"",v)
        n=split(v,arr,",")
        out=""
        for(i=1;i<=n;i++){
            tok=arr[i]
            gsub(/^[ \t]+|[ \t]+$/,"",tok)
            gsub(/^"|"$/,"",tok)
            gsub(/^[ \t]+|[ \t]+$/,"",tok)
            if(tok!="") out=(out==""?tok:out" "tok)
        }
        return out
    }
    BEGIN{ section=""; dc=0 }
    {
        line=$0
        t=line; sub(/^[ \t]*/,"",t)
        if (t=="" || t ~ /^#/) next
        m=match(line,/[^ ]/); indent=(m>0)?m-1:0
        if (indent==0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            ci=index(line,":"); section=substr(line,1,ci-1); next
        }
        lt=line; sub(/^[ \t]+/,"",lt)
        isitem=0
        if (lt ~ /^- /) { sub(/^- /,"",lt); isitem=1 }
        ci=index(lt,":"); if (ci==0) next
        k=substr(lt,1,ci-1); gsub(/[ \t]/,"",k)
        v=strip(substr(lt,ci+1))
        if (section=="device_pool") {
            if (isitem && k=="id") {
                dc++
                printf "MT_DEVICE_%d_ID=%c%s%c\n", dc, 39, v, 39
            } else if (dc>0) {
                if (k=="adb_serial")   printf "MT_DEVICE_%d_ADB=%c%s%c\n", dc, 39, v, 39
                if (k=="model")        printf "MT_DEVICE_%d_MODEL=%c%s%c\n", dc, 39, v, 39
                if (k=="capabilities") printf "MT_DEVICE_%d_CAPS=%c%s%c\n", dc, 39, flowlist(v), 39
            }
        } else if (section=="lease_policy") {
            gsub(/[^A-Za-z0-9_]/,"_",k)
            printf "MT_LEASE_%s=%c%s%c\n", k, 39, flowlist(v), 39
        }
    }
    END{ printf "MT_DEVICE_COUNT=%c%d%c\n", 39, dc, 39 }
    ' "$1"
}

# Loads MT_DEVICE_* + MT_LEASE_* into the caller shell. Safe to call alongside
# mt_load_config (disjoint variable namespaces).
mt_load_pool() {
    cfg=$1
    [ -r "$cfg" ] || { echo "mt_load_pool: unreadable $cfg" >&2; return 1; }
    i=1
    while [ "$i" -le "${MT_DEVICE_COUNT:-0}" ]; do
        unset "MT_DEVICE_${i}_ID" "MT_DEVICE_${i}_ADB" "MT_DEVICE_${i}_MODEL" \
              "MT_DEVICE_${i}_CAPS" 2>/dev/null || true
        i=$((i + 1))
    done
    MT_DEVICE_COUNT=0
    eval "$(mt__parse_pool_awk "$cfg")"
    export MT_DEVICE_COUNT
    return 0
}

# --- scalar/list config-key accessors (READ-only queries; set NO shell vars) --
# These are QUERY functions (print to stdout), NOT loaders — they never mutate
# the caller shell (disjoint from mt_load_config / mt_load_pool). Each takes the
# config-file path as $1 (same contract as mt_load_config). §11.4.28(B): the
# VALUES they read are consumer config data; NO project literal lives here.

# Print the configured `conductor:` alias (§11.4.177 auto-conductor, top-level
# scalar key). Empty output when the key is absent OR set to an empty string
# (=> no alias is the conductor; the /home session is conductor by default).
# The resolver treats a session whose alias == this value as "no worktree /
# stay on /home". Consumer-overridable.
mt_config_conductor() {
    cfg=${1:-}
    [ -r "$cfg" ] || return 1
    awk '
    BEGIN{ sq=sprintf("%c",39); dq=sprintf("%c",34); done=0 }
    function strip(v,   i){
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        if (substr(v,1,1)==sq){ v=substr(v,2); i=index(v,sq); if(i>0)v=substr(v,1,i-1); return v }
        if (substr(v,1,1)==dq){ v=substr(v,2); i=index(v,dq); if(i>0)v=substr(v,1,i-1); return v }
        sub(/[ \t]*#.*$/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); return v
    }
    /^conductor:/ && !done { v=$0; sub(/^conductor:[ \t]*/,"",v); print strip(v); done=1 }
    ' "$cfg"
}

# Print the top-level `excluded_aliases:` set — ONE alias per line (ATM-834).
#
# WHY (§11.4.187(4) / §11.4.6): the engine previously read exactly ONE
# machine-readable alias-policy scalar (`conductor:`). A consumer whose policy
# excludes FURTHER aliases (a dead/disabled subscription, an operator-excluded
# alias) could only state that in PROSE COMMENTS, which the engine cannot read —
# so a documented-as-excluded alias was still positionally mapped onto a track.
# This accessor makes that set MACHINE-READABLE. It is purely ADDITIVE: an
# absent key prints NOTHING, so every existing config behaves exactly as before.
#
# Accepted YAML shapes (top-level key only):
#   excluded_aliases: [a, b]        # flow sequence, optionally quoted
#   excluded_aliases: a, b          # bare comma/space list
#   excluded_aliases:               # block sequence
#     - a
#     - b
# Trailing `#` comments are stripped. The VALUES are consumer config data;
# NO project literal lives here (§11.4.28(B) / §11.4.177).
mt_config_excluded_aliases() {
    cfg=${1:-}
    [ -r "$cfg" ] || return 1
    awk '
    BEGIN{ sq=sprintf("%c",39); dq=sprintf("%c",34); inblk=0 }
    function clean(v){
        sub(/[ \t]*#.*$/,"",v)
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        gsub(sq,"",v); gsub(dq,"",v)
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        return v
    }
    function emit(list,   n,i,a,t){
        gsub(/^\[/,"",list); gsub(/\]$/,"",list)
        gsub(/,/," ",list)
        n=split(list,a," ")
        for(i=1;i<=n;i++){ t=clean(a[i]); if(t!="") print t }
    }
    /^excluded_aliases:/ {
        v=$0; sub(/^excluded_aliases:[ \t]*/,"",v); v=clean(v)
        if (v!="") { emit(v); inblk=0 } else { inblk=1 }
        next
    }
    # block-sequence continuation: indented "- item" lines until the next
    # top-level key (a non-indented, non-blank line).
    inblk==1 {
        if ($0 ~ /^[ \t]+-[ \t]*/) { v=$0; sub(/^[ \t]+-[ \t]*/,"",v); v=clean(v); if(v!="") print v; next }
        if ($0 ~ /^[ \t]*$/) next
        inblk=0
    }
    ' "$cfg"
}

# Print the top-level `worktree_subdir:` value (§11.4.111 stable-name resolution
# — the G2b resolver fix). Mirrors mt_config_conductor(): greps the top-level
# `^worktree_subdir:` key, strips surrounding quotes + trailing comment. Empty
# output when the key is absent, so consumers without it fall through to the
# basename default = zero change (§11.4.92 additive/opt-in).
mt_config_worktree_subdir() {
    cfg=${1:-}
    [ -r "$cfg" ] || return 1
    awk '
    BEGIN{ sq=sprintf("%c",39); dq=sprintf("%c",34); done=0 }
    function strip(v,   i){
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        if (substr(v,1,1)==sq){ v=substr(v,2); i=index(v,sq); if(i>0)v=substr(v,1,i-1); return v }
        if (substr(v,1,1)==dq){ v=substr(v,2); i=index(v,dq); if(i>0)v=substr(v,1,i-1); return v }
        sub(/[ \t]*#.*$/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); return v
    }
    /^worktree_subdir:/ && !done { v=$0; sub(/^worktree_subdir:[ \t]*/,"",v); print strip(v); done=1 }
    ' "$cfg"
}

# Print the `fallback.signatures:` list, ONE signature per line (§11.4.177
# auto-fallback / DESIGN §4(b)). Block-style YAML only:
#   fallback:
#     signatures:
#       - '"apiErrorStatus":429'
#       - '"isApiErrorMessage":true'
# Surrounding single OR double quotes are stripped (so a value that ITSELF
# contains double-quotes is single-quoted in YAML and returned verbatim inside).
# Empty output when no fallback/signatures block exists. Consumer-overridable
# (a future rate-limit wording change is a one-line config pin — §11.4.6/§11.4.111).
mt_config_fallback_signatures() {
    cfg=${1:-}
    [ -r "$cfg" ] || return 1
    awk '
    BEGIN{ sq=sprintf("%c",39); dq=sprintf("%c",34); infb=0; insig=0 }
    function strip_q(v,   i){
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        if (substr(v,1,1)==sq){ v=substr(v,2); i=index(v,sq); if(i>0)v=substr(v,1,i-1); return v }
        if (substr(v,1,1)==dq){ v=substr(v,2); i=index(v,dq); if(i>0)v=substr(v,1,i-1); return v }
        sub(/[ \t]*#.*$/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); return v
    }
    {
        line=$0
        t=line; sub(/^[ \t]*/,"",t)
        if (t=="" || t ~ /^#/) next
        # a top-level (indent-0) key toggles the active section
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            key=line; sub(/:.*/,"",key)
            infb=(key=="fallback")?1:0; insig=0; next
        }
        if (!infb) next
        lt=line; sub(/^[ \t]+/,"",lt)
        if (lt ~ /^signatures:/) { insig=1; next }
        if (lt ~ /^- /) { if (insig){ v=lt; sub(/^- /,"",v); print strip_q(v) } next }
        # any other sub-key under fallback ends the signatures list
        if (lt ~ /^[A-Za-z_][A-Za-z0-9_]*:/) { insig=0 }
    }
    ' "$cfg"
}

# --- LIVE drive detection, matched by STABLE SERIAL (§11.4.111) ---------------
# Output line format:  SERIAL|DEV|MOUNTS|HASCHILD
#   SERIAL   = disk serial (stable id; NEVER the nvmeX ordinal)
#   DEV      = /dev/<name>
#   MOUNTS   = comma-joined mountpoints of the disk AND its partitions
#   HASCHILD = 1 if the disk has partitions/children, else 0
mt_detect_drives() {
    if [ -n "${MT_FIXTURE_DRIVES:-}" ]; then
        # deterministic test seam — no root, no hardware
        printf '%s\n' "$MT_FIXTURE_DRIVES"
        return 0
    fi
    command -v lsblk >/dev/null 2>&1 || { echo "mt_detect_drives: lsblk missing" >&2; return 1; }
    # -P = key="value" pairs, one disk per line: a serial-less disk can NOT
    # column-shift and corrupt the parse of the NEXT disk (§11.4.111 LOW fix).
    # -d = whole disks only; -n no header; explicit column order NAME,TYPE,SERIAL.
    lsblk -dno NAME,TYPE,SERIAL -P 2>/dev/null | while IFS= read -r line; do
        name=$(printf   '%s\n' "$line" | sed -n 's/.*NAME="\([^"]*\)".*/\1/p')
        type=$(printf   '%s\n' "$line" | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
        serial=$(printf '%s\n' "$line" | sed -n 's/.*SERIAL="\([^"]*\)".*/\1/p')
        [ "$type" = "disk" ] || continue
        [ -n "$name" ] || continue
        dev="/dev/$name"
        mounts=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -v '^[[:space:]]*$' | paste -sd, - 2>/dev/null)
        rows=$(lsblk -no NAME "$dev" 2>/dev/null | grep -c .)
        haschild=0
        [ "${rows:-1}" -gt 1 ] && haschild=1
        printf '%s|%s|%s|%s\n' "$serial" "$dev" "$mounts" "$haschild"
    done
}

# --- fail-closed live readers (used by the destructive re-guard path) ---------
# Sentinel meaning "the mount list could NOT be read". The guard fails CLOSED on
# it — DISTINCT from a genuinely-empty mount string (which is allowed). §11.4.133
: "${MT_MOUNTS_UNREADABLE:=__MT_MOUNTS_UNREADABLE__}"

# Read a whole-disk's mountpoints (disk + partitions), comma-joined, on stdout.
#   return 0 = read OK (stdout may be empty for a genuinely-empty disk)
#   return 1 = COULD NOT read (lsblk missing / not a block device / lsblk error)
#              -> caller MUST treat as UNREADABLE and fail CLOSED (§11.4.133).
mt_read_disk_mounts() {
    _dev=$1
    command -v lsblk >/dev/null 2>&1 || return 1
    [ -b "$_dev" ] || return 1
    _raw=$(lsblk -no MOUNTPOINT "$_dev" 2>/dev/null) || return 1
    printf '%s' "$_raw" | grep -v '^[[:space:]]*$' | paste -sd, -
    return 0
}

# Print $dev's CURRENT live serial on stdout (empty if unknown/unreadable).
mt_live_serial() {
    _d=$1
    command -v lsblk >/dev/null 2>&1 || return 0
    lsblk -dno SERIAL "$_d" 2>/dev/null | head -n1 | tr -d '[:space:]'
}

# --- protect-guard primitives -------------------------------------------------
mt_serial_protected() {
    # 0 = serial IS in protected_drives (EXACT match, not substring)
    s=$1
    [ -n "$s" ] || return 1
    # §11.4.111 LOW: disable globbing so a serial containing a shell metachar
    # can't glob-expand during the (still IFS-word-split) loop; restore the
    # caller's prior noglob state afterwards.
    case $- in *f*) _mt_hadf=1 ;; *) _mt_hadf=0 ;; esac
    set -f
    _mt_rc=1
    for p in $MT_PROTECTED_SERIALS; do
        if [ "$p" = "$s" ]; then _mt_rc=0; break; fi
    done
    [ "$_mt_hadf" = 1 ] || set +f
    return "$_mt_rc"
}

mt_mounts_protected() {
    # 0 = the mount set contains a system mountpoint (/, /boot*, /home*)
    mounts=$1
    case ",$mounts," in
        *,/,*)          return 0 ;;   # exact root
        *,/boot*)       return 0 ;;
        *,/home*)       return 0 ;;
    esac
    # also catch a mount that is exactly "/" as the whole field
    [ "$mounts" = "/" ] && return 0
    return 1
}

# HARD protect-guard — call before EVERY destructive step. 0 = SAFE, 1 = REFUSE.
mt_protect_guard() {
    dev=$1; serial=$2; mounts=$3
    # >>MT_MUT_EMPTY_SERIAL (paired §1.1 mutation target — do not remove marker)
    # Fail CLOSED on an unidentifiable target: a safety guard must NEVER ALLOW a
    # disk it cannot positively identify by serial (§11.4.133 / §11.4.111) —
    # independent of the mount check.
    if [ -z "$serial" ]; then
        printf 'REFUSE: %s has EMPTY/unknown serial — cannot positively identify (fail-closed §11.4.133) — NOT touching\n' \
            "$dev" >&2
        return 1
    fi
    # <<MT_MUT_EMPTY_SERIAL
    # Fail CLOSED when the live mount list could not be read (DISTINCT from a
    # genuinely-empty mount set): we cannot verify it is not a system disk.
    if [ "$mounts" = "${MT_MOUNTS_UNREADABLE:-__MT_MOUNTS_UNREADABLE__}" ]; then
        printf 'REFUSE: %s mount list UNREADABLE — cannot verify not-a-system-disk (fail-closed §11.4.133) — NOT touching\n' \
            "$dev" >&2
        return 1
    fi
    if mt_serial_protected "$serial"; then
        printf 'REFUSE: %s serial=%s is in protected_drives (§11.4.133) — NOT touching\n' \
            "$dev" "$serial" >&2
        return 1
    fi
    if mt_mounts_protected "$mounts"; then
        printf 'REFUSE: %s carries a system mountpoint [%s] (belt-and-suspenders) — NOT touching\n' \
            "$dev" "$mounts" >&2
        return 1
    fi
    return 0
}

# Interactive per-drive serial confirmation — the §11.4.133 HUMAN GATE. Reads the
# operator's typed serial from the CONTROLLING TERMINAL (/dev/tty), NEVER from
# stdin — so it truly prompts the keyboard even when the caller's stdin is a pipe
# / here-doc (the illusory-confirmation bug this fixes). 0 = confirmed
# (typed == serial); 1 = mismatch / aborted / no-tty / unknown-serial (fail-closed).
#   $1 dev  $2 serial  $3 assume_yes(0|1)
mt_confirm_serial() {
    _dev=$1; _serial=$2; _yes=${3:-0}
    [ -n "$_serial" ] || return 1
    if [ "$_yes" = "1" ]; then
        printf '    [--yes] auto-confirming %s with serial %s\n' "$_dev" "$_serial"
        return 0
    fi
    if [ ! -c /dev/tty ] || [ ! -r /dev/tty ]; then
        printf '    >> no controlling terminal (/dev/tty) — cannot confirm %s (fail-closed)\n' "$_dev" >&2
        return 1
    fi
    printf '    CONFIRM prep of %s by typing its serial (%s): ' "$_dev" "$_serial" > /dev/tty
    IFS= read -r _ans < /dev/tty || _ans=""
    # >>MT_MUT_CONFIRM (paired §1.1 mutation target — do not remove this marker)
    [ "$_ans" = "$_serial" ] || return 1
    # <<MT_MUT_CONFIRM
    return 0
}

# §11.4.111 TOCTOU guard — re-resolve $dev's LIVE serial and require it to STILL
# equal the plan-time serial AND not be protected. 0 = same non-protected drive;
# 1 = node reassigned / serial changed / now-protected / unreadable (fail-closed).
#   $1 dev  $2 expected(plan-time) serial
mt_verify_live_serial() {
    _dev=$1; _expect=$2
    [ -n "$_expect" ] || return 1
    _cur=$(mt_live_serial "$_dev")
    # >>MT_MUT_TOCTOU (paired §1.1 mutation target — do not remove this marker)
    if [ -z "$_cur" ] || [ "$_cur" != "$_expect" ]; then
        printf 'REFUSE: %s live serial [%s] != plan serial [%s] — node reassigned (§11.4.111) — NOT touching\n' \
            "$_dev" "$_cur" "$_expect" >&2
        return 1
    fi
    if mt_serial_protected "$_cur"; then
        printf 'REFUSE: %s live serial [%s] is PROTECTED at execute time (§11.4.133) — NOT touching\n' \
            "$_dev" "$_cur" >&2
        return 1
    fi
    # <<MT_MUT_TOCTOU
    return 0
}

# --- dynamic track -> live-drive plan -----------------------------------------
# Binds each config track to its declared serial IF that serial is live AND
# passes the protect-guard AND the disk is empty. Emits one TRACK line per
# config track + a UNASSIGNED line per live non-protected serial not in config,
# then TRACKS_READY=<count>.
mt_plan() {
    drives=$(mt_detect_drives)
    ready=0
    i=1
    matched_serials=" "
    # SC2154: tid/tserial/tmount/trole ARE assigned below via `eval "tid=..."`
    # (dynamic per-track vars); shellcheck cannot trace the eval, so the warning
    # is a false positive — suppressed for this loop only (no behaviour change).
    # shellcheck disable=SC2154
    while [ "$i" -le "$MT_TRACK_COUNT" ]; do
        eval "tid=\${MT_TRACK_${i}_ID:-}"
        eval "tserial=\${MT_TRACK_${i}_SERIAL:-}"
        eval "tmount=\${MT_TRACK_${i}_MOUNT:-}"
        eval "trole=\${MT_TRACK_${i}_ROLE:-}"
        # §11.4.187 default single-track mode: a track with NO drive_serial is a
        # plain DIRECTORY, not a drive — never probe lsblk for it and never call
        # it ABSENT (a §11.4.201 false-refusal). Report it honestly by whether
        # the directory exists. Purely additive: every configured track carries a
        # drive_serial, so this branch cannot fire for an existing config.
        if [ -z "$tserial" ]; then
            if [ -d "$tmount" ]; then
                printf 'TRACK %s SERIAL=- DEV=- MOUNT=%s ROLE=%s STATUS=READY-DIR\n' \
                    "$tid" "$tmount" "$trole"
                ready=$((ready + 1))
            else
                printf 'TRACK %s SERIAL=- DEV=- MOUNT=%s ROLE=%s STATUS=MISSING-DIR\n' \
                    "$tid" "$tmount" "$trole"
            fi
            i=$((i + 1))
            continue
        fi
        line=$(printf '%s\n' "$drives" | awk -F'|' -v s="$tserial" '$1==s{print; exit}')
        if [ -z "$line" ]; then
            printf 'TRACK %s SERIAL=%s DEV=- MOUNT=%s ROLE=%s STATUS=ABSENT\n' \
                "$tid" "$tserial" "$tmount" "$trole"
        else
            dev=$(printf '%s' "$line" | cut -d'|' -f2)
            mounts=$(printf '%s' "$line" | cut -d'|' -f3)
            haschild=$(printf '%s' "$line" | cut -d'|' -f4)
            matched_serials="$matched_serials$tserial "
            if ! mt_protect_guard "$dev" "$tserial" "$mounts" 2>/dev/null; then
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=PROTECTED-CONFLICT\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
            elif [ "$haschild" = "1" ] || [ -n "$mounts" ]; then
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=NON-EMPTY\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
            else
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=READY\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
                ready=$((ready + 1))
            fi
        fi
        i=$((i + 1))
    done
    # live non-protected serials that are not any declared track drive
    printf '%s\n' "$drives" | while IFS='|' read -r s dev mounts haschild; do
        [ -n "$s" ] || continue
        case "$matched_serials" in *" $s "*) continue ;; esac
        if mt_serial_protected "$s"; then
            printf 'DRIVE %s DEV=%s STATUS=PROTECTED\n' "$s" "$dev"
        elif mt_mounts_protected "$mounts"; then
            printf 'DRIVE %s DEV=%s STATUS=PROTECTED-BY-MOUNT MOUNTS=%s\n' "$s" "$dev" "$mounts"
        else
            printf 'DRIVE %s DEV=%s STATUS=UNASSIGNED-CANDIDATE\n' "$s" "$dev"
        fi
    done
    printf 'TRACKS_READY=%d\n' "$ready"
}
