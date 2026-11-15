#!/bin/sh
# =============================================================================
# dependency_register.sh — E6 dependency register: read, verdict resolution and
# the adoption preconditions (T221; FR-013, FR-014, FR-015, FR-020, FR-021).
#
# ── The rule this file mechanises ───────────────────────────────────────────
# An externally named dependency is admitted ONLY on a VERIFIED existence
# verdict that is also mapped to one of the recorded uncovered gaps. Three
# separate facts, none of which implies another:
#
#   verdict            does a real artifact exist?        VERIFIED|AMBIGUOUS|UNVERIFIED
#   capability_status  does it DO the thing?              SHIPPED|CLAIMED|CONTRADICTED|UNREACHABLE
#   gap_mapping        do we actually lack that thing?    a row in the gap table
#
# ── Why capability_status is a SEPARATE axis (A-012) ────────────────────────
# EXISTING IS NOT THE SAME AS WORKING. Measured in Phase 0: several verified
# entries sit at initial release versions, one declares a repository that
# returns 404, and one's "tamper-evident" claim is on inspection only
# "append-only" — which detects nothing if the appender is the party being
# checked. So FR-013 existence verification is NECESSARY BUT NOT SUFFICIENT,
# and a capability claim must be demonstrated rather than read off a project
# description. That is why `adopt` refuses a row whose artifact cannot be cited
# even when its verdict is VERIFIED.
#
# ── Why a name match alone never resolves VERIFIED (FR-015, A-001) ──────────
# 2 of the 21 externally named tools in the Phase-0 census were NAME
# COLLISIONS: a real project carries the name, doing an unrelated job. Name and
# description are therefore read as SEPARATE axes and a name-only match
# resolves AMBIGUOUS. Resolving on the name would admit exactly the entries
# most likely to look adoptable.
#
# ── Why "not found" is worded as an absence on a search path (A-011) ────────
# For at least three of the 6 not-found entries, a real project doing exactly
# the described job exists UNDER A DIFFERENT NAME. That reads as garbled
# recall, not invention, and the remedy differs: search for the capability, do
# not conclude the capability is imaginary. So an UNVERIFIED verdict must be
# worded as an absence on ONE SEARCH PATH; a non-existence claim is refused.
#
# ── Why the sweep precondition is checked FIRST (FR-021) ────────────────────
# A missing sweep result is NOT "no findings". That is the same false-null this
# whole feature exists to close (§11.4.201(6)): a broken instrument and a clean
# tree return the identical quiet zero.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   dependency_register.sh validate <register.jsonl>
#   dependency_register.sh resolve  <name> <description> <candidates.tsv>
#   dependency_register.sh adopt    <register.jsonl> <name> <gaps.tsv> <sweep_result>
#   dependency_register.sh --selftest
#
#   register line (E6):
#     {"name","verdict","artifact_url","gap_mapping","capability_status","covered_by"}
#   candidates.tsv : <name>\t<description>\t<artifact_url>
#   gaps.tsv       : <gap_id>\t<description>\t<covering_rule_anchor>
#
# ── Exit status ─────────────────────────────────────────────────────────────
#   0 accepted / valid · 1 refused / invalid · 2 unreadable input (fail-closed)
#
# ── Parsing note (measured trap class 5) ────────────────────────────────────
# Fields are read with shell parameter expansion, not `sed 's/.*"k".../'`: a
# leading greedy `.*` binds to the LAST occurrence of a key on the line.
#
# Deps  : POSIX sh, grep, cut. Xref: data-model.md E6 · spec.md A-001/A-011/A-012
# =============================================================================

set -u

DR_VERDICTS='VERIFIED AMBIGUOUS UNVERIFIED'
DR_CAP_STATUS='SHIPPED CLAIMED CONTRADICTED UNREACHABLE'

# _field <line> <key> — first occurrence, parameter expansion only.
#
# NAME AND CALL SHAPE ARE PART OF THE PUBLISHED CONTRACT. The reference fixture
# scripts/testing/anti_slop/fixtures/ref/dependency_ref.sh declares this seam
# API *and its code shape*, because the paired §1.1 mutations edit named lines
# and marker-delimited blocks in whatever implementation is live. Landing a real
# seam with the same CLI but different internals silently turned five demonstrated
# mutation pairs into no-ops — the pairs still ran, they just stopped proving
# anything. Inheriting the shape, not only the interface, is what keeps them
# load-bearing (§11.4.115(F)).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
_field() {
    _dr_l=$1; _dr_k="\"$2\""
    case $_dr_l in *"$_dr_k"*) : ;; *) printf ''; return 1 ;; esac
    _dr_v=${_dr_l#*"$_dr_k"}
    _dr_v=${_dr_v#*:}
    while :; do
        case $_dr_v in
            " "*) _dr_v=${_dr_v# } ;;
            "	"*) _dr_v=${_dr_v#	} ;;
            *) break ;;
        esac
    done
    case $_dr_v in '"'*) : ;; *) printf ''; return 1 ;; esac
    _dr_v=${_dr_v#\"}
    printf '%s' "${_dr_v%%\"*}"
    return 0
}

# Internal alias retained so existing call sites read naturally.
_dr_str() { _field "$@"; }

_dr_in_set() {  # <value> <set>
    for _dr_x in $2; do [ "$_dr_x" = "$1" ] && return 0; done
    return 1
}

# A citable artifact vs an explicit statement. Both are legal in the REGISTER
# (FR-013); only a citable one is legal at ADOPTION (A-012).
_dr_is_citable() {
    case ${1:-} in
        http://*|https://*|git@*|ssh://*|file://*) return 0 ;;
        *) return 1 ;;
    esac
}

# A-011: an UNVERIFIED verdict states an absence on a search path. A claim of
# non-existence is a different, unsupported assertion and is refused.
# NOTE the deliberately distinct temp name: an earlier draft used _dr_n here,
# which is the ENTRY COUNTER in dr_validate. Because this helper is called
# DIRECTLY (not through a command substitution, which would have given it a
# subshell) it silently reset the counter and the validator reported
# "register VALID (0 entries)" over 21 accepted entries — a clean, confident,
# wrong answer of exactly the class this feature exists to catch.
_dr_nonexistence_claim() {
    _dr_nec=$(printf '%s\n' "${1:-}" | grep -Eic 'does not exist|non-?existent|never existed|is fabricated|was invented|imaginary' || true)
    [ "${_dr_nec:-0}" -gt 0 ]
}

dr_validate() {  # <register>
    _dr_reg=${1:-}
    if [ -z "$_dr_reg" ] || [ ! -r "$_dr_reg" ]; then
        printf 'REFUSE store_UNREADABLE(%s) — an unreadable register is refused, never read as empty\n' "${_dr_reg:-<none>}" >&2
        return 2
    fi
    _dr_bad=0; _dr_n=0
    while IFS= read -r _dr_line || [ -n "$_dr_line" ]; do
        [ -n "$_dr_line" ] || continue
        case $_dr_line in \#*) continue ;; esac
        _dr_n=$((_dr_n + 1))
        _dr_name=$(_dr_str "$_dr_line" name) || _dr_name=''
        _dr_v=$(_dr_str "$_dr_line" verdict) || _dr_v=''
        _dr_a=$(_dr_str "$_dr_line" artifact_url) || _dr_a=''
        _dr_c=$(_dr_str "$_dr_line" capability_status) || _dr_c=''
        _dr_id=${_dr_name:-<unnamed>}

        if ! _dr_in_set "$_dr_v" "$DR_VERDICTS"; then                            # REG-VERDICT-SET
            printf 'REFUSE entry %s line %s — verdict "%s" not in {VERIFIED,AMBIGUOUS,UNVERIFIED}\n' \
                "$_dr_id" "$_dr_n" "${_dr_v:-<none>}" >&2
            _dr_bad=$((_dr_bad + 1)); continue
        fi
        if [ -z "$_dr_a" ]; then                                                 # REG-EVIDENCE-FIELD
            printf 'REFUSE entry %s line %s — artifact_url EMPTY (FR-013 requires a citable artifact OR an explicit not-found statement)\n' "$_dr_id" "$_dr_n" >&2
            _dr_bad=$((_dr_bad + 1)); continue
        fi
        if ! _dr_in_set "$_dr_c" "$DR_CAP_STATUS"; then
            printf 'REFUSE entry %s line %s — capability_status "%s" not in {SHIPPED,CLAIMED,CONTRADICTED,UNREACHABLE} (A-012: existing is not working)\n' \
                "$_dr_id" "$_dr_n" "${_dr_c:-<none>}" >&2
            _dr_bad=$((_dr_bad + 1)); continue
        fi
        if _dr_nonexistence_claim "$_dr_a"; then
            printf 'REFUSE entry %s line %s — artifact_url claims NON-EXISTENCE; A-011 requires an absence on a search path, not a proof of non-existence\n' \
                "$_dr_id" "$_dr_n" >&2
            _dr_bad=$((_dr_bad + 1)); continue
        fi
        # GUARDED ON NON-EMPTY ON PURPOSE. An EMPTY artifact_url is the
        # REG-EVIDENCE-FIELD check's defect, not this one. Without the guard two
        # checks refuse the same fixture, and the paired §1.1 mutation that
        # removes one of them cannot flip anything — the pair runs, reports
        # PAIR-NOT-DEMONSTRATED, and the surviving check quietly masks the
        # removal. Each check owning exactly one defect is what keeps the
        # mutation load-bearing (§11.4.115(F)) and what makes a refusal name the
        # right thing to fix.
        if [ "$_dr_v" = UNVERIFIED ] && [ -n "$_dr_a" ]; then
            _dr_sp=$(printf '%s\n' "$_dr_a" | grep -Eic 'search path' || true)
            if [ "${_dr_sp:-0}" -eq 0 ]; then
                printf 'REFUSE entry %s line %s — an UNVERIFIED verdict must state the SEARCH PATH the absence was measured on (A-011)\n' \
                    "$_dr_id" "$_dr_n" >&2
                _dr_bad=$((_dr_bad + 1)); continue
            fi
        fi
        printf 'ok   entry %s verdict=%s capability_status=%s artifact=%s\n' "$_dr_id" "$_dr_v" "$_dr_c" "$_dr_a"
    done < "$_dr_reg"

    if [ "$_dr_bad" -eq 0 ]; then
        printf 'register VALID (%s entries)\n' "$_dr_n"
        return 0
    fi
    printf 'register INVALID (%s of %s entries refused)\n' "$_dr_bad" "$_dr_n" >&2
    return 1
}

dr_resolve() {  # <name> <description> <candidates.tsv>
    NAME=${1:?}; DESC=${2:?}; CAND=${3:?}
    if [ ! -r "$CAND" ]; then
        printf 'REFUSE store_UNREADABLE(%s)\n' "$CAND" >&2
        return 2
    fi
    # Name and description are SEPARATE axes (FR-015). Counted, never `grep -q`.
    name_hits=$(grep -Ec "^${NAME}	" -- "$CAND" 2>/dev/null || true)
    if [ "${name_hits:-0}" -eq 0 ]; then
        printf 'UNVERIFIED %s — no candidate carries this name on this search path. This is an absence on one search path, NOT a proof of non-existence (A-011): search for the capability under another name before concluding anything.\n' "$NAME"
        return 0
    fi
    cand_row=$(grep -E "^${NAME}	" -- "$CAND" 2>/dev/null | head -n 1)
    cand_desc=$(printf '%s\n' "$cand_row" | cut -f2)
    cand_url=$(printf '%s\n' "$cand_row" | cut -f3)
    if [ "$cand_desc" = "$DESC" ]; then                                          # RESOLVE-DESC-AXIS
        printf 'VERIFIED %s — name and description both match; artifact=%s\n' "$NAME" "${cand_url:-<none>}"
        return 0
    fi                                                                           # RESOLVE-DESC-AXIS
    printf 'AMBIGUOUS %s — a real project carries this name but its description does not match. wanted [%s] / registry says [%s]. A name match alone never resolves to a positive verdict (FR-015, A-001 name-collision).\n' \
        "$NAME" "$DESC" "$cand_desc"
    return 0
}
dr_adopt() {  # <register> <name> <gaps.tsv> <sweep_result>
    REG=${1:?}; NAME=${2:?}; GAPS=${3:?}; SWEEP=${4:-}
    if [ ! -r "$REG" ]; then
        printf 'REFUSE store_UNREADABLE(%s)\n' "$REG" >&2
        return 2
    fi

    # ---- FR-021 adoption-side precondition, checked FIRST -------------------
    # A missing or empty sweep result is NOT "no findings". `! -s` covers the
    # absent, unreadable and zero-byte cases in one test.
    if [ -z "$SWEEP" ] || [ ! -s "$SWEEP" ]; then                                # ADOPT-SWEEP-PRECOND
        printf 'REFUSE %s — the wiring sweep has produced no result for the current tree state (expected at: %s). A missing or empty sweep result is NOT "no findings"; it is an unread instrument, and reading it as zero is the false null this feature exists to close.\n' \
            "$NAME" "${SWEEP:-<none>}" >&2
        return 1
    fi                                                                           # ADOPT-SWEEP-PRECOND

    row=$(grep -F "\"name\":\"${NAME}\"" -- "$REG" 2>/dev/null | head -n 1)
    if [ -z "$row" ]; then
        printf 'REFUSE %s — no register entry; an unregistered dependency has no verdict at all, which is not the same as a positive one\n' "$NAME" >&2
        return 1
    fi

    v=$(_field "$row" verdict) || v=''
    if [ "$v" != "VERIFIED" ]; then                                              # ADOPT-VERDICT-CHECK
        printf 'REFUSE %s — dependency_NOT_VERIFIED(verdict=%s). Adoption requires a VERIFIED existence verdict; %s is not one (FR-014).\n' \
            "$NAME" "${v:-<none>}" "${v:-<none>}" >&2
        return 1
    fi                                                                           # ADOPT-VERDICT-CHECK

    # ---- A-012: existing is not working -------------------------------------
    artifact=$(_field "$row" artifact_url) || artifact=''
    if ! _dr_is_citable "$artifact"; then
        printf 'REFUSE %s — dependency_ARTIFACT_NOT_CITABLE(artifact_url=%s). The verdict is VERIFIED but the artifact cannot be cited from this tree, and per A-012 existence read off a description is not a demonstrated capability.\n' \
            "$NAME" "${artifact:-<none>}" >&2
        return 1
    fi

    gm=$(_field "$row" gap_mapping) || gm=''
    gap_hits=0
    if [ -r "$GAPS" ]; then
        gap_hits=$(grep -Ec "^${gm}	" -- "$GAPS" 2>/dev/null || true)
    else
        printf 'REFUSE %s — the recorded gap table is unreadable at %s; with no gap table every mapping is undecidable and an undecidable mapping is refused, not assumed uncovered\n' \
            "$NAME" "$GAPS" >&2
        return 1
    fi
    if [ "${gap_hits:-0}" -eq 0 ]; then
        cover=$(_field "$row" covered_by)                                        # ADOPT-COVERING-RULE
        printf 'REFUSE %s — dependency_GAP_UNMAPPED(gap_mapping=%s). This capability is ALREADY COVERED by %s — bind to that seam instead of adopting a second mechanism for it (FR-018 refuses the restatement).\n' \
            "$NAME" "${gm:-<none>}" "${cover:-<covering rule NOT recorded — record it before refusing again, a bare rejection tells the proposer nothing>}" >&2
                                                                                 # ADOPT-COVERING-RULE
        return 1
    fi

    printf 'ALLOW %s — VERIFIED, artifact citable, and mapped to recorded uncovered gap %s; sweep result read from %s\n' \
        "$NAME" "$gm" "$SWEEP"
    return 0
}

# --- selftest: golden-good / golden-bad / negative-control -------------------
dr_selftest() {
    _st_d=$(mktemp -d) || return 2
    _st_bad=0
    _st() { if [ "$2" -eq "$3" ]; then printf 'SELFTEST %-38s ok   (%s)\n' "$1" "$4";
            else printf 'SELFTEST %-38s BAD  expected rc=%s got rc=%s (%s)\n' "$1" "$2" "$3" "$4"; _st_bad=$((_st_bad+1)); fi; }

    R="$_st_d/reg.jsonl"; G="$_st_d/gaps.tsv"; S="$_st_d/sweep.txt"; C="$_st_d/cand.tsv"
    {
      printf '%s\n' '{"name":"ok-mapped","verdict":"VERIFIED","artifact_url":"https://example.invalid/a","gap_mapping":"G1","capability_status":"SHIPPED","covered_by":""}'
      printf '%s\n' '{"name":"ok-unver","verdict":"UNVERIFIED","artifact_url":"not found on this search path (npm, PyPI, crates.io)","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}'
      printf '%s\n' '{"name":"ok-amb","verdict":"AMBIGUOUS","artifact_url":"https://example.invalid/collision","gap_mapping":"G3","capability_status":"CLAIMED","covered_by":""}'
      printf '%s\n' '{"name":"covered","verdict":"VERIFIED","artifact_url":"https://example.invalid/c","gap_mapping":"G9","capability_status":"SHIPPED","covered_by":"CM-EXAMPLE-RULE"}'
      printf '%s\n' '{"name":"uncitable","verdict":"VERIFIED","artifact_url":"verified but URL not transcribed","gap_mapping":"G1","capability_status":"CLAIMED","covered_by":""}'
    } > "$R"
    printf 'G1\thash-chained ledger\tSS1\nG2\tstat oracle\tSS2\nG3\ttool reality\tSS3\nG4\tdeclare intent\tSS4\n' > "$G"
    printf 'sweep result for tree-state deadbeef: 0 unreferenced gates\n' > "$S"
    printf 'us2-collider\ta build-cache proxy\thttps://example.invalid/x\n' > "$C"

    dr_validate "$R" >/dev/null 2>&1; _st GG-validate-clean 0 $? 'golden-good register validates'

    B="$_st_d/bad_verdict.jsonl"; cp "$R" "$B"
    printf '%s\n' '{"name":"bad-v","verdict":"PROBABLY","artifact_url":"https://x.invalid/y","gap_mapping":"G1","capability_status":"SHIPPED","covered_by":""}' >> "$B"
    dr_validate "$B" >/dev/null 2>&1; _st GB-verdict-out-of-set 1 $? 'golden-bad: verdict outside the closed set'

    B2="$_st_d/bad_ev.jsonl"; cp "$R" "$B2"
    printf '%s\n' '{"name":"bad-e","verdict":"UNVERIFIED","artifact_url":"","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}' >> "$B2"
    dr_validate "$B2" >/dev/null 2>&1; _st GB-empty-evidence 1 $? 'golden-bad: empty artifact_url'

    B3="$_st_d/bad_ne.jsonl"; cp "$R" "$B3"
    printf '%s\n' '{"name":"bad-n","verdict":"UNVERIFIED","artifact_url":"this project does not exist","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}' >> "$B3"
    dr_validate "$B3" >/dev/null 2>&1; _st GB-nonexistence-claim 1 $? 'golden-bad: non-existence claim (A-011)'

    dr_validate "$_st_d/no_such_register.jsonl" >/dev/null 2>&1; _st GB-unreadable-register 2 $? 'golden-bad: unreadable register fails closed'

    dr_adopt "$R" ok-mapped "$G" "$S"  >/dev/null 2>&1; _st NC-adopt-mapped 0 $? 'negative control: VERIFIED+mapped is ADMITTED'
    dr_adopt "$R" ok-unver "$G" "$S"   >/dev/null 2>&1; _st GB-adopt-unverified 1 $? 'golden-bad: UNVERIFIED refused'
    dr_adopt "$R" ok-amb "$G" "$S"     >/dev/null 2>&1; _st GB-adopt-ambiguous 1 $? 'golden-bad: AMBIGUOUS refused'
    dr_adopt "$R" covered "$G" "$S"    >/dev/null 2>&1; _st GB-adopt-covered 1 $? 'golden-bad: already-covered gap refused'
    dr_adopt "$R" uncitable "$G" "$S"  >/dev/null 2>&1; _st GB-adopt-uncitable 1 $? 'golden-bad: VERIFIED but artifact not citable (A-012)'
    dr_adopt "$R" ok-mapped "$G" "$_st_d/absent.txt" >/dev/null 2>&1; _st GB-adopt-no-sweep 1 $? 'golden-bad: absent sweep result'
    : > "$_st_d/empty_sweep.txt"
    dr_adopt "$R" ok-mapped "$G" "$_st_d/empty_sweep.txt" >/dev/null 2>&1; _st GB-adopt-empty-sweep 1 $? 'golden-bad: empty sweep result'

    _o=$(dr_resolve us2-collider 'a hash-chained tool-call ledger' "$C" 2>&1)
    case $_o in *AMBIGUOUS*) printf 'SELFTEST %-38s ok   (name-only match resolves AMBIGUOUS)\n' GB-resolve-name-collision ;;
        *) printf 'SELFTEST %-38s BAD  got [%s]\n' GB-resolve-name-collision "$_o"; _st_bad=$((_st_bad+1)) ;; esac
    _o=$(dr_resolve us2-collider 'a build-cache proxy' "$C" 2>&1)
    case $_o in *VERIFIED*) printf 'SELFTEST %-38s ok   (exact match resolves VERIFIED)\n' NC-resolve-exact ;;
        *) printf 'SELFTEST %-38s BAD  got [%s]\n' NC-resolve-exact "$_o"; _st_bad=$((_st_bad+1)) ;; esac

    rm -rf "$_st_d"
    printf 'SELFTEST-SUMMARY bad=%s\n' "$_st_bad"
    [ "$_st_bad" -eq 0 ] || return 1
    return 0
}

case ${1:-} in
    validate) shift; dr_validate "$@"; exit $? ;;
    resolve)  shift; dr_resolve  "$@"; exit $? ;;
    adopt)    shift; dr_adopt    "$@"; exit $? ;;
    --selftest) dr_selftest; exit $? ;;
    '') : ;;
    *) printf 'unknown subcommand "%s" (want validate|resolve|adopt|--selftest)\n' "$1" >&2; exit 2 ;;
esac
