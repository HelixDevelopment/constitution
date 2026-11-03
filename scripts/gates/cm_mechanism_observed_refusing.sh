#!/bin/sh
# =============================================================================
# cm_mechanism_observed_refusing.sh — CM-MECHANISM-OBSERVED-REFUSING gate (T229).
#
# ── What this gate asserts (FR-007) ─────────────────────────────────────────
#   MOR-A0  the E3 mechanism registry is present                  (structural)
#   MOR-A1  GOLDEN-BAD      : a mechanism with NO first_refusal_ref
#                             mints no verdict                       (RUNTIME)
#   MOR-A2  NEGATIVE CONTROL: a mechanism WITH a resolvable
#                             first-refusal record IS accepted       (RUNTIME)
#   MOR-A3  GOLDEN-BAD      : a first_refusal_ref that resolves to
#                             nothing is refused like an absent one  (RUNTIME)
#   MOR-A4  every mechanism in the REAL registry resolves          (structural)
#   MOR-A5  the rule is WIRED at the acceptance seam               (structural)
#
# ── Why MOR-A2 is the load-bearing half ─────────────────────────────────────
# Without it, FR-007 degenerates into "no mechanism is ever trusted" — a gate
# that refuses everything is not stricter, it is broken, and §11.4.201(1) rates
# that false refusal exactly as seriously as a false pass. A2 is the negative
# control the task text requires by name.
#
# ── Why MOR-A3 exists ───────────────────────────────────────────────────────
# A pointer to no record is not a record. Accepting a `first_refusal_ref` field
# merely because it is non-empty would make the requirement satisfiable by
# typing a path, which is the paperwork-instead-of-evidence failure the whole
# feature exists to close.
#
# ── Why MOR-A5 may FAIL, honestly ───────────────────────────────────────────
# §11.4.108: a registry no acceptance seam consults refuses nothing. If A5
# FAILs, the honest reading is that the reader-seam wiring (feature task T225)
# has not landed — not that this gate is broken.
#
# Usage : cm_mechanism_observed_refusing.sh [--registry <path>] [--reader <path>] [--selftest]
# Output: CN-VERDICT / CN-SUMMARY. Exit 0 only when nothing FAILed or was BLIND.
# Deps  : POSIX sh, grep, mktemp. Read-only w.r.t. the repository.
# Xref  : FR-007 · FR-022 · data-model.md E3 · §11.4.115(F)
# =============================================================================

set -u

GATE_ID=CM-MECHANISM-OBSERVED-REFUSING
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# Default root = where the gate LIVES (the superproject when vendored as a submodule, else the canon itself), never the
# directory above the canon: "../../.." from a standalone canon is a foreign directory outside the repository.
# shellcheck disable=SC1091
[ -r "$SELF_DIR/../lib/default_scan_root.sh" ] && . "$SELF_DIR/../lib/default_scan_root.sh" && REPO=$(cm_default_scan_root "$SELF_DIR") || REPO=""
# A copy of the gate staged somewhere without scripts/lib (a paired-mutation sandbox) falls back to the legacy
# consumer-layout depth it was staged at.
[ -n "$REPO" ] || REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer (only way to get the honest SKIP)

REGISTRY="$REPO/docs/requests/verification_mechanisms.jsonl"
READER="$REPO/scripts/lib/critical_blocker_gate.sh"
DO_SELFTEST=0
while [ $# -gt 0 ]; do
    case $1 in
        --registry) REGISTRY=$2; shift 2 ;;
        --reader)   READER=$2;   shift 2 ;;
        --standalone-canon) STANDALONE=1; shift ;;
        --selftest) DO_SELFTEST=1; shift ;;
        -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

cn_reset
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_mor.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

# --- the rule, as one function so A1/A2/A3 all exercise the SAME code path ----
# mor_admit <registry> <mechanism_id> <repo-root>
#   rc 0 = the mechanism may mint verdicts; rc 1 = refused, reason on stdout.
mor_admit() {
    _mor_reg=$1; _mor_id=$2; _mor_root=$3
    if [ ! -r "$_mor_reg" ]; then
        printf 'REFUSE mechanism_REGISTRY_UNREADABLE(%s) — fail-closed: an unreadable registry is not an empty one\n' "$_mor_reg"
        return 1
    fi
    _mor_row=$(grep -F "\"mechanism_id\":\"${_mor_id}\"" -- "$_mor_reg" 2>/dev/null | head -n 1)
    if [ -z "$_mor_row" ]; then
        printf 'REFUSE mechanism_NEVER_OBSERVED_REFUSING(%s) — the mechanism is not registered at all, so no refusal has ever been recorded for it\n' "$_mor_id"
        return 1
    fi
    case $_mor_row in
        *'"first_refusal_ref"'*) : ;;
        *)
            printf 'REFUSE mechanism_NEVER_OBSERVED_REFUSING(%s) — no first_refusal_ref: this mechanism has never been observed refusing a known-bad case, so it is unvalidated instrumentation and mints nothing\n' "$_mor_id"
            return 1 ;;
    esac
    # first occurrence via parameter expansion (no greedy sed — trap class 5)
    _mor_v=${_mor_row#*'"first_refusal_ref"'}
    _mor_v=${_mor_v#*:}
    _mor_v=${_mor_v#*\"}
    _mor_ref=${_mor_v%%\"*}
    if [ -z "$_mor_ref" ]; then
        printf 'REFUSE mechanism_NEVER_OBSERVED_REFUSING(%s) — first_refusal_ref is EMPTY\n' "$_mor_id"
        return 1
    fi
    _mor_p=$_mor_ref
    case $_mor_p in /*) : ;; *) _mor_p="$_mor_root/$_mor_ref" ;; esac
    if [ ! -s "$_mor_p" ]; then
        printf 'REFUSE mechanism_NEVER_OBSERVED_REFUSING(%s) — first_refusal_ref points at %s, which is missing or empty. A pointer to no record is not a record.\n' "$_mor_id" "$_mor_ref"
        return 1
    fi
    printf 'ALLOW %s — observed refusing a known-bad case; record at %s\n' "$_mor_id" "$_mor_ref"
    return 0
}

# --- A0 -----------------------------------------------------------------------
if [ ! -r "$REGISTRY" ] && [ "$STANDALONE" -eq 1 ]; then
    cn_skip MOR-A0-REGISTRY-PRESENT "standalone canon DECLARED (--standalone-canon): the E3 mechanism registry is consumer data and does not exist here (honest SKIP, not a PASS)"
elif [ -r "$REGISTRY" ]; then
    cn_pass MOR-A0-REGISTRY-PRESENT "the E3 mechanism registry is present: $REGISTRY"
else
    cn_fail MOR-A0-REGISTRY-PRESENT "the E3 mechanism registry is absent or unreadable at $REGISTRY — with no registry every mechanism is unvalidated, which is a refusal, not a pass"
fi

# --- A1 GOLDEN-BAD -------------------------------------------------------------
printf '{"mechanism_id":"probe-unobserved","paired_mutation_ref":"p","golden_good_ref":"g","golden_bad_ref":"b","negative_control_ref":"n"}\n' > "$TMP/reg.jsonl"
_out=$(mor_admit "$TMP/reg.jsonl" probe-unobserved "$REPO"); _rc=$?
_n=$(printf '%s\n' "$_out" | grep -Ec 'mechanism_NEVER_OBSERVED_REFUSING' || true)
if [ "$_rc" -ne 0 ] && [ "${_n:-0}" -gt 0 ]; then
    cn_pass MOR-A1-UNOBSERVED-REFUSED "a mechanism with no first_refusal_ref mints no verdict, and the refusal names the reason verbatim: $_out"
else
    cn_fail MOR-A1-UNOBSERVED-REFUSED "an unvalidated mechanism was admitted (rc=$_rc): $_out"
fi

# --- A2 NEGATIVE CONTROL -------------------------------------------------------
printf 'REFUSE golden-bad fixture rejected by probe-observed rc=1\n' > "$TMP/first_refusal.log"
printf '{"mechanism_id":"probe-observed","first_refusal_ref":"%s","paired_mutation_ref":"p","golden_good_ref":"g","golden_bad_ref":"b","negative_control_ref":"n"}\n' "$TMP/first_refusal.log" > "$TMP/reg2.jsonl"
_out=$(mor_admit "$TMP/reg2.jsonl" probe-observed "$REPO"); _rc=$?
if [ "$_rc" -eq 0 ]; then
    cn_pass MOR-A2-OBSERVED-ADMITTED "a mechanism WITH a resolvable first-refusal record IS admitted: $_out"
else
    cn_fail MOR-A2-OBSERVED-ADMITTED "a mechanism that WAS observed refusing was still rejected ($_out) — FR-007 has degenerated into 'no mechanism is ever trusted', a false-refusal engine (§11.4.201(1))"
fi

# --- A3 GOLDEN-BAD: a reference that resolves to nothing ----------------------
printf '{"mechanism_id":"probe-dangling","first_refusal_ref":"%s/no_such_record.log","paired_mutation_ref":"p","golden_good_ref":"g","golden_bad_ref":"b","negative_control_ref":"n"}\n' "$TMP" > "$TMP/reg3.jsonl"
_out=$(mor_admit "$TMP/reg3.jsonl" probe-dangling "$REPO"); _rc=$?
if [ "$_rc" -ne 0 ]; then
    cn_pass MOR-A3-DANGLING-REF-REFUSED "a first_refusal_ref that resolves to nothing is refused like an absent one: $_out"
else
    cn_fail MOR-A3-DANGLING-REF-REFUSED "a dangling first_refusal_ref was accepted — the requirement would be satisfiable by typing a path"
fi

# --- A4 the real registry resolves --------------------------------------------
if [ -r "$REGISTRY" ]; then
    _bad=0; _seen=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case $_line in \#*) continue ;; esac
        _id=${_line#*'"mechanism_id"'}; _id=${_id#*:}; _id=${_id#*\"}; _id=${_id%%\"*}
        _seen=$((_seen + 1))
        if ! mor_admit "$REGISTRY" "$_id" "$REPO" >/dev/null 2>&1; then
            cn_fail MOR-A4-REAL-REGISTRY-RESOLVES "registered mechanism '$_id' does not resolve to a recorded refusal — it is registered but unvalidated"
            _bad=$((_bad + 1))
        fi
    done < "$REGISTRY"
    if [ "$_seen" -eq 0 ]; then
        cn_blind MOR-A4-REAL-REGISTRY-RESOLVES "the registry parsed to ZERO mechanism rows — the reader saw nothing, so 'all mechanisms resolve' would be vacuous; reporting blindness, not compliance (§11.4.201(6))"
    elif [ "$_bad" -eq 0 ]; then
        cn_pass MOR-A4-REAL-REGISTRY-RESOLVES "all $_seen registered mechanism(s) resolve to a recorded refusal"
    fi
elif [ "$STANDALONE" -eq 1 ]; then
    cn_skip MOR-A4-REAL-REGISTRY-RESOLVES "standalone canon DECLARED (--standalone-canon): no consumer registry to resolve (honest SKIP, not a PASS)"
else
    cn_fail MOR-A4-REAL-REGISTRY-RESOLVES "registry unreadable at $REGISTRY"
fi

# --- A5 wired at the seam ------------------------------------------------------
cn_count '-E' 'open_blocker_gate' "$READER"
_needle_hits=$CN_COUNT
if [ ! -r "$READER" ] && [ "$STANDALONE" -eq 1 ]; then
    cn_skip MOR-A5-WIRED-AT-SEAM "standalone canon DECLARED (--standalone-canon): the acceptance seam $READER belongs to a consumer (honest SKIP, not a PASS)"
elif [ ! -r "$READER" ]; then
    cn_blind MOR-A5-WIRED-AT-SEAM "the acceptance seam is unreadable at $READER — the wiring question is UNDECIDED"
elif [ "${_needle_hits:-0}" -eq 0 ]; then
    cn_blind MOR-A5-WIRED-AT-SEAM "control needle 'open_blocker_gate' returned 0 hits in $READER through the same grep and flags — the instrument cannot see, so its zero says NOTHING (§11.4.201(7)(b))"
else
    cn_count '-E' 'mechanism_NEVER_OBSERVED_REFUSING' "$READER"
    if [ "${CN_COUNT:-0}" -gt 0 ]; then
        cn_pass MOR-A5-WIRED-AT-SEAM "the acceptance seam emits the FR-007 refusal reason (${CN_COUNT} reference(s))"
    else
        cn_fail MOR-A5-WIRED-AT-SEAM "the FR-007 rule is implemented here but the acceptance seam $READER never emits mechanism_NEVER_OBSERVED_REFUSING (needle saw the file ${_needle_hits}x, so this absence is REAL). §11.4.108: a registry no seam consults refuses nothing. HONEST READING: the reader-seam wiring (feature task T225) has not landed; this gate is working."
    fi
fi

cn_summary "$GATE_ID"
_summary_rc=$?

if [ "$DO_SELFTEST" -eq 1 ]; then
    printf '\n--- --selftest triple ---\n'
    printf 'golden-BAD       no first_refusal_ref        -> MOR-A1 must refuse\n'
    printf 'golden-BAD       dangling first_refusal_ref  -> MOR-A3 must refuse\n'
    printf 'NEGATIVE CONTROL resolvable first-refusal    -> MOR-A2 must ADMIT\n'
    printf 'A gate passing A1 and A3 while failing A2 refuses every mechanism and is broken, not strict.\n'
fi

exit "$_summary_rc"
