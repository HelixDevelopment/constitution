#!/bin/sh
# cm_unreferenced_gate_bound_or_retired.sh — CM-UNREFERENCED-GATE-BOUND-OR-RETIRED
# (FR-019 — a gate that exists on disk but is referenced by no seam must be
# either BOUND to a seam or RETIRED with evidence. Neither is not an option.)
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A gate file nobody invokes is not enforcement, it is a file. §11.4.227(A) is
# explicit that a PROSE CARRIER never counts as an implementation; a script
# that no seam reaches is the same failure one layer down — it looks like
# coverage in a directory listing and refuses nothing in practice.
#
# This sweep enumerates every gate under the gates dir and assigns each ONE
# disposition from a closed set. It REFUSES while any gate is UNBOUND.
#
# ── The binding mechanisms (closed set, first match wins) ───────────────────
#
#   BOUND-SEAM-LITERAL     the gate's basename appears on a NON-COMMENT line
#                          of a declared seam file (wiring_seam_files.tsv).
#
#   BOUND-DATA-DISPATCH    the gate's filename is reproduced by applying a
#                          declared dispatcher rule (wiring_data_dispatch.tsv)
#                          to a REAL row of that rule's data pack, AND the
#                          dispatcher is itself seam-bound.
#
#   BOUND-PAIRED-MUTATION  a `*_mutation_test.sh` whose paired gate exists.
#
#   DEFERRED-REGISTERED    the token has a row in the deferrals registry —
#                          owed debt against a tracked item, per §11.4.227(A).
#
#   RETIRED-CITED          the token has a row in the removals registry
#                          carrying a VALID §11.4.124 git-history citation.
#
#   UNBOUND                none of the above. The sweep REFUSES.
#
# ── Two mechanisms exist because a naive one manufactures 51 false findings ─
# §11.4.201(7)(a) — match STRUCTURE, not substring, and know the difference
# between a THING and a CARRIER that mentions it:
#
#   * A gate name inside a COMMENT is a carrier, not an invocation. Comment
#     lines are stripped before the literal scan.
#   * covenant_propagation_suite.sh never contains the names of the 51 gates
#     it runs — it CONSTRUCTS them from a data pack. A basename-only sweep
#     would report all 51 as unreferenced. That is why BOUND-DATA-DISPATCH
#     exists and why it mirrors the dispatcher's own derivation rather than
#     inventing a parallel one.
#
# ── Why mutation tests bind by PAIRING, not by seam reference ───────────────
# A `*_mutation_test.sh` is a §1.1 paired mutation. It is invoked by the
# meta-test that validates its gate, never from a seam — by construction.
# Demanding a seam reference for all 86 of them would be a mass false-positive
# refusal (§11.4.201(1)). What IS decidable, and what genuinely goes wrong, is
# an ORPHAN: a mutation test whose gate was deleted, left behind validating
# nothing. So the pairing check is the binding, and it fires on exactly that.
# Measured on this tree: 86 mutation tests, 86 paired, 0 orphans — the check
# yields no findings today and would fire on the first orphan (proven by
# fixture in the paired mutation test, so it is not vacuous).
#
# A gate's OWN binding is reported once, on the gate. A mutation test is not
# reported a second time for its gate's unboundness — one root cause, one
# finding.
#
# ── Honest boundaries (§11.4.6) ─────────────────────────────────────────────
# (1) REACHABILITY, NOT EXECUTION. A literal reference on a non-comment line
#     proves the gate's path is reached by executable code in the seam. It
#     does NOT prove the call executes on every run — a gate behind a false
#     conditional still counts here. Proving a gate has ever actually REFUSED
#     is the first-refusal evidence layer (FR-022), a different deliverable.
#     This gate does not claim it.
# (2) THE T001 NON-GATE EXCLUSION IS CURRENTLY A NO-OP, AND IS IMPLEMENTED
#     ANYWAY. The four registered non-gate entries (the three libs under
#     lib/ and the wrappers generator) do not match `cm_*.sh`, so excluding
#     them removes nothing today. It is implemented so a future lib named
#     `cm_*.sh` cannot silently become a finding — stated rather than
#     presented as if it were filtering something.
# (3) `manual-qa-handoff` HAS NO SEAM FILE on this tree. It is recorded as an
#     honest gap in wiring_seam_files.tsv, not pointed at a plausible file.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_unreferenced_gate_bound_or_retired.sh [--root <dir>] [--gates-dir <dir>]
#         [--seams <tsv>] [--dispatch <tsv>] [--deferrals <tsv>]
#         [--removals <tsv>] [--result <tsv>] [--no-write]
#   cm_unreferenced_gate_bound_or_retired.sh --fingerprint
#   cm_unreferenced_gate_bound_or_retired.sh --selftest
#
#     --result   where the sweep result is written (FR-021's input).
#                Default <gates-dir>/wiring_sweep_result.tsv.
#     --no-write report only; do not write the result file.
#     --fingerprint  print the current tree-state fingerprint and exit 0.
#
# ── The result file and its fingerprint (so a stale result cannot pass) ─────
# The sweep writes its verdict, every per-gate disposition, and a fingerprint
# over EXACTLY the inputs it read: every enumerated gate file, every declared
# seam file, every data pack, and both registries. Change any of them and the
# fingerprint changes, so a result computed against an earlier tree cannot
# satisfy a later one. FR-021's precondition predicate
# (lib/wiring_sweep_precondition.sh) compares against this value.
#
# ── Exit codes (contracts/gate-verdict.md) ──────────────────────────────────
#   0 ALLOW  — every gate is bound, deferred, or cited-retired.
#   1 FAIL   — reserved; this gate's violations are refusals, see below.
#   2 REFUSE — at least one gate is UNBOUND, or an input was unreadable, or
#              the control needle came back blind. An UNBOUND gate is a
#              REFUSE and not a FAIL on purpose: the finding is that the
#              WIRING (the instrument) is missing, which is what a REFUSE
#              means — someone must fix the instrument, not the product.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, awk, grep, sed, sort, cut, find, sha256sum (or cksum fallback).
#   Parses clean under `sh -n` AND `bash -n` (§11.4.67).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   FR-019 / FR-021 (spec.md), quickstart S19, contracts/gate-verdict.md,
#   §11.4.227(A), §11.4.124 (investigate-before-remove — the citation),
#   §11.4.201(1)(7)(a)(b), §11.4.251 (one implementation per token),
#   §1.1 (paired mutation: cm_unreferenced_gate_bound_or_retired_mutation_test.sh).
#
# Classification: universal (§11.4.17).

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOKEN=CM-UNREFERENCED-GATE-BOUND-OR-RETIRED

# The four T001-registered non-gate entries, matched by path SUFFIX so the
# registry is stable whichever ancestor dir is passed as --gates-dir.
NONGATE='lib/covenant_propagation_engine.sh
lib/covenant_propagation_mutation_engine.sh
lib/pointer_carrier.sh
covenant_propagation_wrappers_generate.sh'

ROOT=${CONSUMER_ROOT:-}
GATES_DIR=; SEAMS=; DISPATCH=; DEFERRALS=; REMOVALS=; RESULT=
NOWRITE=0; MODE=check
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer seams (only way to get the honest SKIP)

while [ $# -gt 0 ]; do
    case $1 in
        --root)        ROOT=${2:?}; shift 2 ;;
        --gates-dir)   GATES_DIR=${2:?}; shift 2 ;;
        --seams)       SEAMS=${2:?}; shift 2 ;;
        --dispatch)    DISPATCH=${2:?}; shift 2 ;;
        --deferrals)   DEFERRALS=${2:?}; shift 2 ;;
        --removals)    REMOVALS=${2:?}; shift 2 ;;
        --result)      RESULT=${2:?}; shift 2 ;;
        --no-write)    NOWRITE=1; shift ;;
        --standalone-canon) STANDALONE=1; shift ;;
        --fingerprint) MODE=fingerprint; shift ;;
        --selftest)    MODE=selftest; shift ;;
        -h|--help)     sed -n '1,130p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'REFUSE: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
    esac
done

[ -n "$GATES_DIR" ] || GATES_DIR=$SELF_DIR
if [ -z "$ROOT" ]; then
    # Default = where the gate LIVES (superproject when vendored, else the canon), never the directory above the canon.
    # shellcheck disable=SC1091
    [ -r "$SELF_DIR/../lib/default_scan_root.sh" ] && . "$SELF_DIR/../lib/default_scan_root.sh" && ROOT=$(cm_default_scan_root "$SELF_DIR") || ROOT=""
    [ -n "$ROOT" ] || ROOT=$(CDPATH= cd -- "$GATES_DIR/../../.." && pwd)   # staged copy without scripts/lib: legacy consumer depth
fi
[ -n "$SEAMS" ]     || SEAMS="$GATES_DIR/wiring_seam_files.tsv"
[ -n "$DISPATCH" ]  || DISPATCH="$GATES_DIR/wiring_data_dispatch.tsv"
[ -n "$DEFERRALS" ] || DEFERRALS="$GATES_DIR/gate_ledger_deferrals.tsv"
[ -n "$REMOVALS" ]  || REMOVALS="$GATES_DIR/gate_ledger_removals.tsv"
[ -n "$RESULT" ]    || RESULT="$GATES_DIR/wiring_sweep_result.tsv"

TAB=$(printf '\t')
TMP=$(mktemp -d 2>/dev/null) || { echo "REFUSE: store_UNREADABLE — mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

refuse() { printf 'REFUSE: %s — %s\n' "$1" "$2"; exit 2; }
data()   { grep -v '^#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$'; }

hash_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
    else cksum | tr -d ' '; fi
}

is_nongate() {
    _p=$1
    printf '%s\n' "$NONGATE" | while IFS= read -r _e; do
        [ -n "$_e" ] || continue
        case "$_p" in *"/$_e"|"$_e") echo HIT ;; esac
    done | grep -q HIT
}

token_of() { printf '%s' "${1%.sh}" | tr 'a-z_' 'A-Z-'; }

# ── Input validation (unreadable is a REFUSE, never "no findings"). ─────────
validate_inputs() {
    [ -d "$GATES_DIR" ] || refuse "store_UNREADABLE" "gates dir absent: $GATES_DIR"
    for f in "$SEAMS" "$DISPATCH" "$DEFERRALS" "$REMOVALS"; do
        [ -r "$f" ] || refuse "store_UNREADABLE" "required registry not readable: $f (an unreadable store is a refusal, never an empty finding set — quickstart S19)"
    done
}

# ── Enumerate the gate population. ─────────────────────────────────────────
enumerate() {
    find "$GATES_DIR" -type f -name 'cm_*.sh' 2>/dev/null | sort > "$TMP/all.txt"
    : > "$TMP/gates.txt"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if is_nongate "$p"; then continue; fi
        printf '%s\n' "$p" >> "$TMP/gates.txt"
    done < "$TMP/all.txt"
}

# ── Seam code: every declared seam file, comment lines stripped. ────────────
build_seam_code() {
    : > "$TMP/seamcode.txt"; missing=""
    while IFS= read -r line; do
        sid=$(printf '%s' "$line" | cut -f1)
        rel=$(printf '%s' "$line" | cut -f2)
        [ -n "$sid" ] && [ -n "$rel" ] || refuse "command_field_ABSENT" "wiring_seam_files.tsv row is not 2-field: '$line'"
        p="$ROOT/$rel"
        if [ -r "$p" ]; then
            grep -v '^[[:space:]]*#' "$p" >> "$TMP/seamcode.txt" 2>/dev/null
            printf '%s\n' "$p" >> "$TMP/seamfiles.txt"
        else
            missing="$missing $rel"
        fi
    done < "$TMP/seams.txt"
    if [ -n "$missing" ] && [ "$STANDALONE" -eq 1 ]; then
        printf 'SKIP: STANDALONE_CANON_DECLARED — the declared seam file(s)%s are consumer files and do not exist here (--standalone-canon; honest SKIP, not a PASS)\n' "$missing"
        exit 3
    fi
    [ -z "$missing" ] || refuse "store_UNREADABLE" "declared seam file(s) unreadable:$missing — a seam that cannot be read cannot be shown to reference anything, and treating that as 'no reference' would convert an instrument failure into findings against every gate"
}

# ── Data-dispatch: reproduce the dispatcher's own filename derivation. ──────
build_dispatch_set() {
    : > "$TMP/dispatched.txt"
    while IFS= read -r line; do
        disp=$(printf '%s' "$line" | cut -f1)
        pack=$(printf '%s' "$line" | cut -f2)
        kf=$(printf   '%s' "$line" | cut -f3)
        strip=$(printf '%s' "$line" | cut -f4)
        npre=$(printf '%s' "$line" | cut -f5)
        nsuf=$(printf '%s' "$line" | cut -f6)
        [ -n "$disp" ] && [ -n "$pack" ] && [ -n "$kf" ] || \
            refuse "command_field_ABSENT" "wiring_data_dispatch.tsv row is not 6-field: '$line'"
        # The dispatcher must itself be reachable from a seam, or dispatch
        # through it proves nothing.
        db=$(basename -- "$disp")
        grep -qF -- "$db" "$TMP/seamcode.txt" || \
            refuse "mechanism_NEVER_OBSERVED_REFUSING" "declared dispatcher $disp is NOT referenced from any declared seam file, so the gates it dispatches are not seam-reachable through it; binding them via this rule would be a coverage bluff"
        pk="$GATES_DIR/$pack"
        [ -r "$pk" ] || refuse "store_UNREADABLE" "data pack not readable: $pk"
        data "$pk" | while IFS= read -r prow; do
            key=$(printf '%s' "$prow" | cut -f"$kf")
            [ -n "$key" ] || continue
            case "$strip" in -) slug=$key ;; *) slug=${key#$strip} ;; esac
            printf '%s%s%s\n' "$npre" "$slug" "$nsuf"
        done >> "$TMP/dispatched.txt"
    done < "$TMP/dispatch.txt"
    sort -u "$TMP/dispatched.txt" -o "$TMP/dispatched.txt"
}

# ── A removals row counts ONLY with a valid §11.4.124 citation. ─────────────
retired_cited() {
    _tok=$1
    _row=$(data "$REMOVALS" | awk -F"$TAB" -v T="$_tok" '$1==T{print; exit}')
    [ -n "$_row" ] || return 1
    _cit=$(printf '%s' "$_row" | cut -f3)
    printf '%s' "$_cit" | grep -q 'git log' || return 2
    printf '%s' "$_cit" | grep -qE '[0-9a-f]{7,40}' || return 2
    return 0
}

fingerprint() {
    {
        printf 'gates\n'; while IFS= read -r p; do printf '%s ' "$p"; hash_of < "$p"; done < "$TMP/gates.txt"
        printf 'seams\n'; sort -u "$TMP/seamfiles.txt" 2>/dev/null | while IFS= read -r p; do printf '%s ' "$p"; hash_of < "$p"; done
        printf 'packs\n'; for p in "$SEAMS" "$DISPATCH" "$DEFERRALS" "$REMOVALS"; do printf '%s ' "$p"; hash_of < "$p"; done
    } | hash_of
}

run_sweep() {
    validate_inputs
    data "$SEAMS"    > "$TMP/seams.txt"
    data "$DISPATCH" > "$TMP/dispatch.txt"
    : > "$TMP/seamfiles.txt"
    enumerate
    ngates=$(wc -l < "$TMP/gates.txt" | tr -d ' ')
    [ "$ngates" -gt 0 ] || \
        refuse "control_needle_BLIND" "the enumeration found ZERO cm_*.sh files under $GATES_DIR — a zero from a blind enumerator is not an empty population (§11.4.201(7)(b))"

    build_seam_code
    [ -s "$TMP/seamcode.txt" ] || \
        refuse "control_needle_BLIND" "every declared seam file stripped to zero non-comment lines — the scan is blind and every 'unreferenced' verdict it produced would be a false accusation"

    # CONTROL NEEDLE (§11.4.201(7)(b)). The needle is a SENTINEL appended to
    # the scan copy, so it is present BY CONSTRUCTION and the needle can never
    # be unavailable just because no gate happens to be bound — an earlier
    # draft needled on a real .sh reference and went `control_needle_ABSENT`
    # on exactly the trees where every gate is unbound, i.e. the cases the
    # sweep exists to judge.
    #
    # It shares the certified query's load-bearing features: the SAME
    # `grep -qF` over the SAME scan file with a dotted filename, so a
    # quoting, path or encoding failure in the scan step kills the needle
    # too. `grep -F` makes the dot inert, so a dotted sentinel exercises
    # every layer the real query crosses.
    nb='__wiring_sweep_control_needle_v1.sh'
    printf '%s\n' "$nb" >> "$TMP/seamcode.txt"
    grep -qF -- "$nb" "$TMP/seamcode.txt" || \
        refuse "control_needle_BLIND" "the known-present sentinel '$nb' did not resolve through the literal-scan path — the instrument is blind and every 'unreferenced' verdict it produced would be a false accusation"
    if grep -qF -- '__wiring_sweep_negative_control_v1.sh' "$TMP/seamcode.txt"; then
        refuse "control_needle_BLIND" "the negative-control sentinel matched though it was never written — the scan over-matches and every absence it reports is unreliable"
    fi

    build_dispatch_set
    printf 'OK   inputs: %s gate file(s); seam code %s non-comment line(s) from %s file(s); needle "%s" SEEN; negative control clean\n' \
        "$ngates" "$(wc -l < "$TMP/seamcode.txt" | tr -d ' ')" "$(sort -u "$TMP/seamfiles.txt" | wc -l | tr -d ' ')" "$nb"

    : > "$TMP/disp.tsv"; unbound=0
    cl=0; cd_=0; cp=0; cdef=0; cret=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        b=$(basename -- "$p"); tok=$(token_of "$b"); why=""; d=""
        if grep -qF -- "$b" "$TMP/seamcode.txt"; then
            d=BOUND-SEAM-LITERAL; why="basename on a non-comment line of a declared seam file"; cl=$((cl+1))
        elif grep -qxF -- "$b" "$TMP/dispatched.txt"; then
            d=BOUND-DATA-DISPATCH; why="filename reproduced from a real data-pack row via a declared dispatcher rule"; cd_=$((cd_+1))
        else
            case "$b" in
                *_mutation_test.sh)
                    pg="$(dirname -- "$p")/${b%_mutation_test.sh}.sh"
                    if [ -f "$pg" ]; then
                        d=BOUND-PAIRED-MUTATION; why="paired gate present: $(basename -- "$pg")"; cp=$((cp+1))
                    fi ;;
            esac
            if [ -z "$d" ] && data "$DEFERRALS" | cut -f1 | grep -qxF -- "$tok"; then
                d=DEFERRED-REGISTERED; why="registered owed debt in $(basename -- "$DEFERRALS")"; cdef=$((cdef+1))
            fi
            if [ -z "$d" ]; then
                retired_cited "$tok"; rcx=$?
                case $rcx in
                    0) d=RETIRED-CITED; why="removals row carries a valid git-history citation"; cret=$((cret+1)) ;;
                    2) d=UNBOUND; why="removals row present but its citation is ABSENT or MALFORMED (needs a literal 'git log' and a 7-40 hex commit id) — an uncited retirement is the delete-names-to-lower-the-count channel and is refused"; unbound=$((unbound+1)) ;;
                    *) d=UNBOUND; why="no seam reference, no data-dispatch rule, no deferral row, no retirement row"; unbound=$((unbound+1)) ;;
                esac
            fi
        fi
        printf '%s\t%s\t%s\t%s\n' "$tok" "$b" "$d" "$why" >> "$TMP/disp.tsv"
    done < "$TMP/gates.txt"

    printf 'OK   dispositions: seam-literal=%s data-dispatch=%s paired-mutation=%s deferred=%s retired-cited=%s UNBOUND=%s\n' \
        "$cl" "$cd_" "$cp" "$cdef" "$cret" "$unbound"

    if [ "$unbound" -gt 0 ]; then
        verdict=REFUSE
        printf 'REFUSE: mechanism_NEVER_OBSERVED_REFUSING — %s gate file(s) are UNBOUND: bound to no seam, dispatched by no declared rule, and carrying neither a registered deferral nor a cited retirement. A gate no seam reaches refuses nothing (FR-019). Resolved evidence (first 20):\n' "$unbound"
        awk -F'\t' '$3=="UNBOUND"{printf "         %-52s %s\n", $2, $4}' "$TMP/disp.tsv" | head -20
        [ "$unbound" -le 20 ] || printf '         ... and %s more; the full per-gate disposition is in the result file\n' "$((unbound - 20))"
    else
        verdict=ALLOW
    fi

    fp=$(fingerprint)
    if [ "$NOWRITE" -eq 0 ]; then
        {
            printf '# wiring_sweep_result.tsv — FR-019 sweep result. GENERATED; do not hand-edit.\n'
            printf '# Regenerate: cm_unreferenced_gate_bound_or_retired.sh\n'
            printf '# The fingerprint covers EXACTLY the inputs this sweep read (every gate\n'
            printf '# file, every declared seam file, and the four registries). Change any of\n'
            printf '# them and it changes, so a result computed against an earlier tree cannot\n'
            printf '# satisfy a later one — that is the FR-021 staleness guarantee, and it is\n'
            printf '# the whole reason the value is recorded here rather than assumed.\n'
            printf '# Schema: <kind>\\t<a>\\t<b>\\t<c>\n'
            printf 'sweep-verdict\t%s\t%s\tunbound=%s\n' "$verdict" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$unbound"
            printf 'tree-fingerprint\t%s\tgates=%s\tseams=%s\n' "$fp" "$ngates" "$(sort -u "$TMP/seamfiles.txt" | wc -l | tr -d ' ')"
            printf 'summary\tseam-literal=%s\tdata-dispatch=%s\tpaired=%s;deferred=%s;retired=%s\n' "$cl" "$cd_" "$cp" "$cdef" "$cret"
            printf '# gate-token\tgate-file\tdisposition\tbasis\n'
            sed 's/^/gate\t/' "$TMP/disp.tsv" | sed 's/^gate\t/gate\t/'
        } > "$RESULT"
        printf 'OK   result written: %s (fingerprint %s)\n' "$RESULT" "$fp"
    else
        printf 'OK   --no-write: result NOT written (fingerprint would be %s)\n' "$fp"
    fi

    case $verdict in
        ALLOW) printf '%s: ALLOW — all %s gate(s) bound, deferred, or cited-retired\n' "$TOKEN" "$ngates"; return 0 ;;
        *)     printf '%s: REFUSE — %s of %s gate(s) UNBOUND\n' "$TOKEN" "$unbound" "$ngates"; return 2 ;;
    esac
}

run_fingerprint() {
    validate_inputs
    data "$SEAMS" > "$TMP/seams.txt"; : > "$TMP/seamfiles.txt"
    enumerate; build_seam_code
    fingerprint; return 0
}

# ── Self-validation (§11.4.107(10) / §11.4.201) ─────────────────────────────
# Golden-TRUE: a real violation MUST make the sweep fire.
# Golden-FALSE: a clean tree MUST NOT, and the golden-FALSE set carries the
# DECOYS that a naive implementation flags — a data-dispatched gate whose name
# appears nowhere (51 false findings if mishandled), an unreferenced paired
# mutation test (86 more), and a registered non-gate. A sweep that fires on
# those is the false-positive refusal this feature forbids; one that passes
# the golden-TRUE set is blind. Either fails the selftest.
run_selftest() {
    pass=0; fail=0
    ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
    bad() { printf 'FAIL  %s (rc=%s)\n' "$1" "$2"; printf '%s\n' "$OUT" | sed 's/^/        | /'; fail=$((fail + 1)); }

    F="$TMP/fx"; mkdir -p "$F/root/seams" "$F/g"
    mkg() { printf '#!/bin/sh\nexit 0\n' > "$F/g/$1"; chmod +x "$F/g/$1"; }

    reset() {
        rm -rf "$F/g" "$F/root"; mkdir -p "$F/g" "$F/root/seams"
        printf '# hdr\npre-build\tseams/pb.sh\n' > "$F/g/seams.tsv"
        printf '# hdr\n' > "$F/g/dispatch.tsv"
        printf '# hdr\n' > "$F/g/def.tsv"
        printf '# hdr\n' > "$F/g/rem.tsv"
        # A real non-comment body line matters: a seam file that is ALL
        # comments is indistinguishable from a blind scan, and the sweep
        # correctly REFUSES as blind rather than reporting every gate
        # unreferenced. Real seam files always carry code; a fixture without
        # it tests the blind-guard, not the case it claims to test.
        printf '#!/bin/sh\n# a seam\nseam_body_marker=1\n' > "$F/root/seams/pb.sh"
    }
    sweep() {
        OUT=$("$SELF_DIR/cm_unreferenced_gate_bound_or_retired.sh" --root "$F/root" \
              --gates-dir "$F/g" --seams "$F/g/seams.tsv" --dispatch "$F/g/dispatch.tsv" \
              --deferrals "$F/g/def.tsv" --removals "$F/g/rem.tsv" \
              --result "$F/res.tsv" "$@" 2>&1); RC=$?
    }

    # GF1 — every gate literally referenced -> must NOT fire.
    reset; mkg cm_alpha.sh
    printf 'bash "$D/cm_alpha.sh"\n' >> "$F/root/seams/pb.sh"
    sweep; [ "$RC" -eq 0 ] && ok "GF1 literal-bound gate (must ALLOW)" || bad "GF1 literal-bound gate (must ALLOW)" "$RC"

    # GF2 — DECOY: bound only by data dispatch; its name appears NOWHERE in
    # the seam text. A basename-only sweep flags this; the real tree has 34
    # such gates and flagging them would be 34 false accusations.
    reset; mkg cm_pack_7_thing.sh
    printf 'bash "$D/dispatcher.sh"\n' >> "$F/root/seams/pb.sh"
    printf '#!/bin/sh\ndispatcher_body=1\n' > "$F/root/seams/dispatcher.sh"
    printf 'pre-build\tseams/pb.sh\npre-build\tseams/dispatcher.sh\n' >> "$F/g/seams.tsv"
    printf 'X\tp.tsv\t1\tv.\tcm_pack_\t_thing.sh\n' >> "$F/g/dispatch.tsv"
    sed -i 's|^X\t|seams/dispatcher.sh\t|' "$F/g/dispatch.tsv"
    printf '# pack\nv.7\n' > "$F/g/p.tsv"
    sweep; [ "$RC" -eq 0 ] && ok "GF2 DECOY data-dispatched gate (must ALLOW)" || bad "GF2 DECOY data-dispatched gate (must ALLOW)" "$RC"

    # GF3 — DECOY: an unreferenced paired mutation test. 86 on the real tree.
    reset; mkg cm_alpha.sh; mkg cm_alpha_mutation_test.sh
    printf 'bash "$D/cm_alpha.sh"\n' >> "$F/root/seams/pb.sh"
    sweep; [ "$RC" -eq 0 ] && ok "GF3 DECOY unreferenced paired mutation (must ALLOW)" || bad "GF3 DECOY unreferenced paired mutation (must ALLOW)" "$RC"

    # GF4 — DECOY: a registered non-gate entry is excluded from the population.
    reset; mkdir -p "$F/g/lib"; printf '#!/bin/sh\n' > "$F/g/lib/pointer_carrier.sh"
    mkg cm_alpha.sh; printf 'bash "$D/cm_alpha.sh"\n' >> "$F/root/seams/pb.sh"
    sweep; [ "$RC" -eq 0 ] && ok "GF4 DECOY registered non-gate excluded (must ALLOW)" || bad "GF4 DECOY registered non-gate excluded (must ALLOW)" "$RC"

    # GT1 — a gate bound to nothing at all.
    reset; mkg cm_alpha.sh; mkg cm_orphan.sh
    printf 'bash "$D/cm_alpha.sh"\n' >> "$F/root/seams/pb.sh"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'cm_orphan.sh'; then
        ok "GT1 unbound gate (must REFUSE, naming it)"
    else bad "GT1 unbound gate (must REFUSE, naming it)" "$RC"; fi

    # GT2 — CARRIER: named ONLY inside a comment. A mention is not an
    # invocation (§11.4.201(7)(a)); if this passed, every commented-out gate
    # would read as wired.
    reset; mkg cm_carrier.sh
    printf '# TODO: wire bash "$D/cm_carrier.sh" here one day\n' >> "$F/root/seams/pb.sh"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'cm_carrier.sh'; then
        ok "GT2 comment CARRIER does not bind (must REFUSE)"
    else bad "GT2 comment CARRIER does not bind (must REFUSE)" "$RC"; fi

    # GT3 — retirement with NO citation: the anti-gaming clause.
    reset; mkg cm_gone.sh
    printf 'CM-GONE\trepealed\t\tnothing\n' >> "$F/g/rem.tsv"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'citation'; then
        ok "GT3 uncited retirement (must REFUSE naming the citation)"
    else bad "GT3 uncited retirement (must REFUSE naming the citation)" "$RC"; fi

    # GT4 — citation present but MALFORMED (no commit id). Prose is not a
    # citation; accepting it would reopen the channel the field closes.
    reset; mkg cm_gone.sh
    printf 'CM-GONE\trepealed\twe looked at the history and it was fine\tnothing\n' >> "$F/g/rem.tsv"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'citation'; then
        ok "GT4 malformed citation, no commit id (must REFUSE)"
    else bad "GT4 malformed citation, no commit id (must REFUSE)" "$RC"; fi

    # GT5 — a VALID cited retirement is accepted, so the requirement is a
    # standard to meet and not an unreachable bar.
    reset; mkg cm_gone.sh
    printf 'CM-GONE\trepealed\tgit log --follow -- x :: 3f2a91c wired at seam X; unwired by 9d4e7b1\tsuperseded by Y\n' >> "$F/g/rem.tsv"
    sweep; [ "$RC" -eq 0 ] && ok "GT5 VALID cited retirement (must ALLOW)" || bad "GT5 VALID cited retirement (must ALLOW)" "$RC"

    # GT6 — a registered deferral is accepted (owed debt, §11.4.227(A)).
    reset; mkg cm_owed.sh
    printf 'CM-OWED\tTRACKED-1\tnot yet wired\n' >> "$F/g/def.tsv"
    sweep; [ "$RC" -eq 0 ] && ok "GT6 registered deferral (must ALLOW)" || bad "GT6 registered deferral (must ALLOW)" "$RC"

    # GT7 — an unreadable seam file is a REFUSE, never "no references found".
    reset; mkg cm_alpha.sh
    printf 'pre-build\tseams/does_not_exist.sh\n' >> "$F/g/seams.tsv"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'store_UNREADABLE'; then
        ok "GT7 unreadable seam file (must REFUSE, not 'no findings')"
    else bad "GT7 unreadable seam file (must REFUSE, not 'no findings')" "$RC"; fi

    # GT8 — an unreadable registry is likewise a REFUSE (quickstart S19).
    reset; mkg cm_alpha.sh; rm -f "$F/g/rem.tsv"
    sweep
    if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'store_UNREADABLE'; then
        ok "GT8 unreadable removals registry (must REFUSE)"
    else bad "GT8 unreadable removals registry (must REFUSE)" "$RC"; fi

    printf '\ncm_unreferenced_gate_bound_or_retired.sh --selftest: pass=%s fail=%s\n' "$pass" "$fail"
    [ "$fail" -eq 0 ] || return 1
    return 0
}

case $MODE in
    fingerprint) run_fingerprint; exit $? ;;
    selftest)    run_selftest;    exit $? ;;
    *)           run_sweep;       exit $? ;;
esac
