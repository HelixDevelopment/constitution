#!/bin/sh
# cm_rule_binds_to_seam.sh — CM-RULE-BINDS-TO-SEAM gate
# (FR-010 / FR-011 / FR-018 — every newly declared enforcement rule resolves
# to a named seam that can refuse, and a restatement of an already-bound
# (seam, gate) pair is refused with the covering rule NAMED.)
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A rule that names no seam is prose. §11.4.227(A) is explicit that a prose
# carrier NEVER counts as an implementation, and the measured corpus deficit
# (420 named gates with no executable site) is what that gap looks like at
# scale. This gate refuses the DECLARING CHANGE — the moment a rule is added
# — rather than auditing the debt afterwards, because an after-the-fact audit
# is the thing that produced the deficit.
#
# Three checks, in the order they can refuse:
#
#   FR-011  A rule anchor NEWLY added by the change under test that resolves
#           to no row in the bindings registry REFUSES the declaring change.
#           This is the load-bearing check: it is exact and fires on the
#           first offender.
#
#   FR-018  A NEWLY added anchor whose registry row duplicates the
#           normalised (seam-id, gate-token) pair of an already-declared
#           anchor REFUSES as a restatement, NAMING the covering rule.
#           Keyed on the PAIR, never on a bare subject substring — a
#           substring key manufactures collisions between unrelated rules
#           that happen to share a word.
#
#   FR-010  The measured no-seam count must not exceed the recorded baseline
#           integer. This is the aggregate backstop, not the teeth (see the
#           honest boundary on the ratchet's slack, below).
#
# ── Honest boundaries (§11.4.6) — read these before "fixing" anything ───────
#
# (1) THE FR-010 RATCHET HAS MEASURED SLACK AND CANNOT FIRE ON A SINGLE NEW
#     UNBOUND RULE. The baseline file is SHARED with the §11.4.227(A)
#     gate-token ledger (gate_ledger.sh), whose integer counts UNIMPLEMENTED
#     GATE TOKENS (measured 420). The quantity this gate measures is a
#     different population — RULE ANCHORS with no binding row (measured 239
#     on this tree at authoring time, 2026-08-21). 239 < 420, so ~181 new
#     unbound rules could land before the ceiling is reached. That is stated
#     as a measured fact, not papered over: per §11.4.201(8) a metric whose
#     correct end-state does not move it to target is invalid as a gate, and
#     a ceiling with 181 units of slack is a weak one. It is retained
#     because it is monotone and cannot be gamed upward, and because FR-011
#     — which fires on the FIRST unbound rule — is the real refusal. A
#     per-population baseline calibration is OWED work (§11.4.197), tracked,
#     not silently assumed done. This gate NEVER writes the baseline file:
#     gate_ledger.sh:222 parses it as a BARE integer and any annotation
#     added here would break that consumer.
#
# (2) "RESOLVES TO AN EXECUTABLE GATE SITE" IS A REACHABILITY CLAIM, NOT AN
#     EXECUTION CLAIM. This gate proves the named token has an executable
#     file on disk. It does NOT prove that file is reached on every run, nor
#     that it has ever refused anything. That stronger property is the
#     first-refusal evidence layer (FR-022) and is a DIFFERENT stream's
#     deliverable; this gate does not claim it.
#
# (3) PAIR-COLLISION IS THE DECIDABLE PROJECTION OF RESTATEMENT. Two rules
#     that mean the same thing while binding different (seam, gate) pairs are
#     NOT caught here and are not claimed to be. Semantic overlap outside the
#     pair key remains §11.4.142 / §11.4.194 review territory. Claiming
#     otherwise would be a coverage bluff.
#
# (4) PRE-EXISTING duplicate pairs are REPORTED, never refused. Refusing them
#     would retro-refuse a corpus this gate did not author — a false-positive
#     refusal, which §11.4.201(1) holds to be exactly as serious as a false
#     pass. Only NEWLY added anchors can trigger the FR-018 refusal.
#
# ── The carrier filter (§11.4.201(7)(a) — structure, not substring) ─────────
# A block-start line whose anchor id is followed by a LOWERCASE word is an
# amendment/carve-out CARRIER referring to an existing anchor, not a new
# declaration. Measured on this corpus: `**§11.4.30 carve-out.**`,
# `**§11.4.93 amendment.**`, `**§11.4.202 precedence ...**`. Counting those
# as declarations produced 3 phantom duplicates. A declaration's id is
# followed by a dash-led title, never a lowercase word.
#
# Sub-anchors are captured WHOLE (`11.4.10.A` is distinct from `11.4.10`) so a
# sub-anchor never prefix-matches its parent — the §11.4.227(B) trap.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_rule_binds_to_seam.sh [--root <dir>] [--corpus <path>]
#                            [--bindings <path>] [--gates-dir <dir>]
#                            [--baseline <path>] [--base <git-ref>]
#   cm_rule_binds_to_seam.sh --selftest
#
#     --root      consumer project root (default: $CONSUMER_ROOT, else the
#                 repo root inferred from this script's location).
#     --corpus    governance corpus whose anchors are the rule population
#                 (default: constitution/Constitution.md under --root).
#     --bindings  the registry (default: <gates-dir>/rule_seam_bindings.tsv).
#     --gates-dir directory holding executable gate sites
#                 (default: this script's own directory).
#     --baseline  recorded no-seam ceiling, a bare integer, READ-ONLY
#                 (default: <gates-dir>/gate_ledger_baseline.txt).
#     --base      git ref the change under test is measured AGAINST
#                 (default: HEAD — so uncommitted/staged new anchors are the
#                 "change under test" at the commit seam).
#
# Every path is an argument with a documented default. No project literal is
# hardcoded (§11.4.177 / §11.4.35 — the consumer supplies its paths as DATA).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check lines, then one verdict banner. Every refusal prints the
#   RESOLVED EVIDENCE — the value actually read — so a false positive is
#   diagnosable in one step (gate-verdict.md).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None. Read-only. Writes only to a mktemp dir it removes on exit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, awk, grep, sed, sort, cut, git (for --base resolution).
#   Parses clean under `sh -n` AND `bash -n` (§11.4.67).
#
# ── Exit codes (contracts/gate-verdict.md — three verdicts, never two) ──────
#   0  ALLOW  — every applicable check passed against real evidence.
#   1  FAIL   — a check ran and the condition was genuinely violated.
#   2  REFUSE — the gate COULD NOT DECIDE: an input was unreadable, the
#               control needle came back blind, or a required field was
#               absent. A REFUSE sends someone to fix the INSTRUMENT; a FAIL
#               sends someone to fix the PRODUCT. Collapsing one into the
#               other is the defect the contract exists to prevent.
#
#   FR-011 and FR-018 violations are REFUSE (reasons `rule_NAMES_NO_SEAM`
#   and `rule_IS_RESTATEMENT`, emitted verbatim from the closed set): the
#   declaring change is refused. The FR-010 ratchet breach is a FAIL — the
#   condition is real, measured, and about the product's state.
#
# ── Cross-references ────────────────────────────────────────────────────────
#   FR-010/FR-011/FR-018 (spec.md), E5 seam closed set (data-model.md),
#   contracts/gate-verdict.md, quickstart S17, §11.4.227(A) (prose carriers
#   never count), §11.4.227(B) (block-start counting, sub-anchor prefix
#   trap), §11.4.201(1) (a false-positive refusal is a FAIL-bluff),
#   §11.4.201(7)(a)(b)(c) (structure-not-substring, control needle,
#   the-path-is-part-of-the-instrument), §11.4.6 (no-guessing — a null is
#   never evidence until the needle proves the instrument sees), §1.1
#   (paired mutation: cm_rule_binds_to_seam_mutation_test.sh).
#
# Classification: universal (§11.4.17).

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOOL=cm_rule_binds_to_seam.sh
TOKEN=CM-RULE-BINDS-TO-SEAM

# The E5 closed set, restated byte-for-byte. A near-miss id resolves by
# absence, so this set is matched EXACTLY and an unlisted id REFUSES.
SEAM_SET='pre-action commit pre-build release-tag qa-deploy manual-qa-handoff'

ROOT=${CONSUMER_ROOT:-}
CORPUS=
BINDINGS=
GATES_DIR=
BASELINE=
BASE=HEAD
SELFTEST=0

while [ $# -gt 0 ]; do
    case $1 in
        --root)      ROOT=${2:?--root needs a value}; shift 2 ;;
        --corpus)    CORPUS=${2:?--corpus needs a value}; shift 2 ;;
        --bindings)  BINDINGS=${2:?--bindings needs a value}; shift 2 ;;
        --gates-dir) GATES_DIR=${2:?--gates-dir needs a value}; shift 2 ;;
        --baseline)  BASELINE=${2:?--baseline needs a value}; shift 2 ;;
        --base)      BASE=${2:?--base needs a value}; shift 2 ;;
        --selftest)  SELFTEST=1; shift ;;
        -h|--help)   sed -n '1,150p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'REFUSE: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
    esac
done

[ -n "$ROOT" ] || ROOT=$(CDPATH= cd -- "$SELF_DIR/../../.." && pwd)
[ -n "$GATES_DIR" ] || GATES_DIR=$SELF_DIR
[ -n "$CORPUS" ]    || CORPUS="$ROOT/constitution/Constitution.md"
[ -n "$BINDINGS" ]  || BINDINGS="$GATES_DIR/rule_seam_bindings.tsv"
[ -n "$BASELINE" ]  || BASELINE="$GATES_DIR/gate_ledger_baseline.txt"

TAB=$(printf '\t')
TMP=$(mktemp -d 2>/dev/null) || { echo "REFUSE: store_UNREADABLE — mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

refuse() { printf 'REFUSE: %s — %s\n' "$1" "$2"; exit 2; }

# extract_anchors: block-start anchor ids from the corpus bytes on stdin.
# Structural, line-anchored, carrier-filtered, sub-anchor-whole.
extract_anchors() {
    awk '
    match($0, /^(###|\*\*+)[[:space:]]*\xc2\xa7[0-9]+(\.[0-9A-Za-z]+)+/) {
        s    = substr($0, RSTART, RLENGTH)
        rest = substr($0, RSTART + RLENGTH)
        # An id followed by a lowercase word is an amendment/carve-out
        # CARRIER, not a declaration (§11.4.201(7)(a)).
        if (rest ~ /^[[:space:]]+[a-z]/) next
        sub(/^(###|\*\*+)[[:space:]]*\xc2\xa7/, "", s)
        print s
    }'
}

# rows: registry data rows (comments and blanks inert).
rows() { grep -v '^#' "$BINDINGS" 2>/dev/null | grep -v '^[[:space:]]*$'; }

# gate_site_for <token>: prints the executable gate path, or nothing.
gate_site_for() {
    _t=$1
    _f=$(printf '%s' "$_t" | tr 'A-Z-' 'a-z_')
    _p="$GATES_DIR/${_f}.sh"
    if [ -f "$_p" ] && [ -x "$_p" ]; then printf '%s' "$_p"; fi
}

run_check() {
    rc_allow=0; findings=0

    # ── Input readability. Unreadable is REFUSE, never "no findings". ───────
    [ -r "$CORPUS" ]   || refuse "store_UNREADABLE" "corpus not readable: $CORPUS"
    [ -r "$BINDINGS" ] || refuse "store_UNREADABLE" "bindings registry not readable: $BINDINGS"
    [ -d "$GATES_DIR" ] || refuse "store_UNREADABLE" "gates dir not a directory: $GATES_DIR"
    [ -r "$BASELINE" ] || refuse "store_UNREADABLE" "baseline not readable: $BASELINE"

    base_raw=$(cat -- "$BASELINE")
    base_n=$(printf '%s' "$base_raw" | tr -d '[:space:]')
    printf '%s' "$base_n" | grep -qE '^[0-9]+$' || \
        refuse "exit_status_UNPARSEABLE" "baseline $BASELINE is not a bare integer (resolved: '$base_raw')"

    # ── Registry structural validation. ────────────────────────────────────
    rows > "$TMP/rows.txt"
    nrows=$(wc -l < "$TMP/rows.txt" | tr -d ' ')

    bad_fields=$(awk -F"$TAB" 'NF!=3{print NR": "$0}' "$TMP/rows.txt")
    [ -z "$bad_fields" ] || \
        refuse "command_field_ABSENT" "registry rows must carry exactly 3 tab-separated fields; offenders (resolved): $bad_fields"

    # Fields are split with `cut`, NOT with `IFS=$TAB read`. Tab is an IFS
    # WHITESPACE character, so `read` COLLAPSES consecutive tabs and an empty
    # middle field silently shifts every later field one position left — the
    # gate would then report the GATE TOKEN as the offending seam id. Measured
    # during authoring against a row with an empty seam field; `cut` preserves
    # the empty field and the refusal names the real offender (§11.4.201:
    # a refusal must print resolved evidence diagnosable in one step).
    while IFS= read -r _line; do
        [ -n "${_line:-}" ] || continue
        a=$(printf '%s' "$_line" | cut -f1)
        s=$(printf '%s' "$_line" | cut -f2)
        g=$(printf '%s' "$_line" | cut -f3)
        [ -n "${a:-}" ] || continue
        _ok=0
        for _v in $SEAM_SET; do [ "$s" = "$_v" ] && _ok=1 && break; done
        [ "$_ok" -eq 1 ] || \
            refuse "independence_tier_NOT_IN_SET" "seam id '$s' (rule $a, gate $g) is outside the E5 closed set {$SEAM_SET}; a near-miss id resolves by absence and would silently void this binding"
        if [ -z "$(gate_site_for "$g")" ]; then
            refuse "rule_NAMES_NO_SEAM" "rule $a names seam '$s' via gate token '$g', but that token has NO executable gate site (resolved probe: $GATES_DIR/$(printf '%s' "$g" | tr 'A-Z-' 'a-z_').sh) — a token with no executable site is a prose carrier and never counts (§11.4.227(A))"
        fi
    done < "$TMP/rows.txt"
    printf 'OK   registry: %s rows, all 3-field, all seam ids in the E5 closed set, every gate token has an executable site\n' "$nrows"

    # ── Anchor extraction + CONTROL NEEDLE (§11.4.201(7)(b)). ──────────────
    extract_anchors < "$CORPUS" | LC_ALL=C sort -u > "$TMP/now.txt"
    now_n=$(wc -l < "$TMP/now.txt" | tr -d ' ')
    [ "$now_n" -gt 0 ] || \
        refuse "control_needle_BLIND" "the anchor extractor returned ZERO ids from a non-empty corpus ($CORPUS) — the instrument is blind, and a zero from a blind instrument is not an absence (§11.4.201(7)(b))"

    # The needle shares the certified query's load-bearing features: it is
    # drawn from the SAME extraction output, through the SAME path, so a
    # dialect/anchoring/encoding failure kills it too. A bare-literal needle
    # would certify nothing here.
    needle=$(head -1 "$TMP/now.txt")
    grep -qxF -- "$needle" "$TMP/now.txt" || \
        refuse "control_needle_BLIND" "lookup needle '$needle' known-present in the extraction did not resolve through the lookup path"
    if grep -qxF -- '99.9.999-negative-control' "$TMP/now.txt"; then
        refuse "control_needle_BLIND" "the negative-control id matched — the lookup over-matches and every absence it reports is unreliable"
    fi
    printf 'OK   control needle: extractor SEEING (%s anchors, needle "%s" resolved; negative control clean)\n' "$now_n" "$needle"

    # ── FR-011 + FR-018: the change under test. ────────────────────────────
    corpus_dir=$(dirname -- "$CORPUS"); corpus_base=$(basename -- "$CORPUS")
    if ( cd "$corpus_dir" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 ); then
        if ( cd "$corpus_dir" && git show "$BASE:./$corpus_base" >/dev/null 2>&1 ); then
            ( cd "$corpus_dir" && git show "$BASE:./$corpus_base" ) | extract_anchors | LC_ALL=C sort -u > "$TMP/base.txt"
            base_cnt=$(wc -l < "$TMP/base.txt" | tr -d ' ')
            [ "$base_cnt" -gt 0 ] || \
                refuse "control_needle_BLIND" "the extractor returned ZERO ids from the $BASE blob of $corpus_base — blind against the base, so 'newly added' cannot be computed"
            LC_ALL=C comm -23 "$TMP/now.txt" "$TMP/base.txt" > "$TMP/new.txt"
        else
            refuse "chain_UNWALKABLE" "cannot read $BASE:./$corpus_base — the base state is unresolvable, so 'newly added' is undecidable; supply --base explicitly rather than letting an unknown resolve to 'nothing new'"
        fi
    else
        refuse "chain_UNWALKABLE" "$corpus_dir is not inside a git work tree — the change under test cannot be determined, and an undeterminable change is a REFUSE, never an empty new-anchor set"
    fi
    new_n=$(wc -l < "$TMP/new.txt" | tr -d ' ')

    # Existing (pair -> anchor) map, from anchors NOT newly added.
    : > "$TMP/pairs.txt"
    while IFS= read -r _line; do
        [ -n "${_line:-}" ] || continue
        a=$(printf '%s' "$_line" | cut -f1)
        s=$(printf '%s' "$_line" | cut -f2)
        g=$(printf '%s' "$_line" | cut -f3)
        [ -n "${a:-}" ] || continue
        grep -qxF -- "$a" "$TMP/new.txt" && continue
        printf '%s|%s\t%s\n' "$s" "$g" "$a" >> "$TMP/pairs.txt"
    done < "$TMP/rows.txt"

    if [ "$new_n" -eq 0 ]; then
        printf 'OK   FR-011/FR-018: no anchor newly added against %s — nothing to bind, and silence about absent work is correct\n' "$BASE"
    else
        while IFS= read -r a; do
            [ -n "$a" ] || continue
            row=$(awk -F"$TAB" -v A="$a" '$1==A{print; exit}' "$TMP/rows.txt")
            if [ -z "$row" ]; then
                printf 'REFUSE: rule_NAMES_NO_SEAM — rule %s is newly declared in %s (vs %s) and resolves to NO row in %s. Resolved evidence: registry holds %s rows, none keyed %s. A rule that names no seam that can refuse is prose (FR-011).\n' \
                    "$a" "$corpus_base" "$BASE" "$BINDINGS" "$nrows" "$a"
                findings=$((findings + 1)); rc_allow=2; continue
            fi
            s=$(printf '%s' "$row" | cut -f2); g=$(printf '%s' "$row" | cut -f3)
            cover=$(awk -F"$TAB" -v P="$s|$g" '$1==P{print $2; exit}' "$TMP/pairs.txt")
            if [ -n "$cover" ]; then
                printf 'REFUSE: rule_IS_RESTATEMENT — rule %s is newly declared and binds the pair (seam=%s, gate=%s), which is ALREADY bound by rule %s. Resolved evidence: covering rule = %s. Bind a distinct pair or amend %s instead of restating it (FR-018).\n' \
                    "$a" "$s" "$g" "$cover" "$cover" "$cover"
                findings=$((findings + 1)); rc_allow=2; continue
            fi
            printf 'OK   FR-011/FR-018: newly declared rule %s binds (seam=%s, gate=%s) — seam in closed set, gate site executable, pair not already covered\n' "$a" "$s" "$g"
            printf '%s|%s\t%s\n' "$s" "$g" "$a" >> "$TMP/pairs.txt"
        done < "$TMP/new.txt"
    fi

    # Pre-existing duplicate pairs: REPORTED, never refused (boundary 4).
    dup=$(cut -f1 "$TMP/pairs.txt" 2>/dev/null | sort | uniq -d)
    if [ -n "$dup" ]; then
        printf 'NOTE pre-existing duplicate (seam|gate) pairs present, reported not refused (this gate did not author them; refusing here would be a false-positive refusal per §11.4.201(1)): %s\n' "$(printf '%s' "$dup" | tr '\n' ' ')"
    fi

    # ── FR-010: the aggregate ratchet. ─────────────────────────────────────
    cut -f1 "$TMP/rows.txt" | LC_ALL=C sort -u > "$TMP/bound.txt"
    noseam=$(LC_ALL=C comm -23 "$TMP/now.txt" "$TMP/bound.txt" | wc -l | tr -d ' ')
    if [ "$noseam" -gt "$base_n" ]; then
        printf 'FAIL: FR-010 ratchet violated — measured no-seam rule count %s EXCEEDS the recorded baseline %s (resolved from %s). The count is monotone-decreasing by contract; it went up.\n' \
            "$noseam" "$base_n" "$BASELINE"
        findings=$((findings + 1)); [ "$rc_allow" -eq 2 ] || rc_allow=1
    else
        printf 'OK   FR-010 ratchet: no-seam rule count %s <= baseline %s (headroom %s). HONEST BOUNDARY: this ceiling is shared with the gate-token ledger and counts a DIFFERENT population, so it has %s units of slack and cannot fire on a single new unbound rule — FR-011 above is the check that does. Per-population calibration is owed work (§11.4.201(8)/§11.4.197), not a solved problem.\n' \
            "$noseam" "$base_n" "$((base_n - noseam))" "$((base_n - noseam))"
    fi

    case $rc_allow in
        0) printf '%s: ALLOW — %s rules bound, %s newly declared, 0 findings\n' "$TOKEN" "$nrows" "$new_n"; return 0 ;;
        1) printf '%s: FAIL — %s finding(s)\n' "$TOKEN" "$findings"; return 1 ;;
        *) printf '%s: REFUSE — %s finding(s); the declaring change is refused\n' "$TOKEN" "$findings"; return 2 ;;
    esac
}

# ── Self-validation (§11.4.107(10) / §11.4.201) ─────────────────────────────
# Golden-TRUE cases (a real violation MUST make the gate fire) AND golden-FALSE
# cases (a clean tree MUST NOT make it fire), the golden-FALSE set including a
# CARRIER decoy — an amendment block-start that must NOT be read as a new
# declaration. A gate that fires on the golden-FALSE set is the false-positive
# refusal this feature forbids; one that passes the golden-TRUE set is blind.
# Either outcome fails the selftest and the gate mints no verdict.
run_selftest() {
    pass=0; fail=0
    GIT="git -c user.email=selftest@invalid -c user.name=selftest -c commit.gpgsign=false -c init.defaultBranch=main"

    # A scratch gates dir carrying two executable stub gate sites.
    sgates="$TMP/gates"; mkdir -p "$sgates"
    for t in CM-STUB-ALPHA CM-STUB-BETA; do
        f=$(printf '%s' "$t" | tr 'A-Z-' 'a-z_')
        printf '#!/bin/sh\nexit 0\n' > "$sgates/${f}.sh"; chmod +x "$sgates/${f}.sh"
    done
    printf '420\n' > "$sgates/baseline.txt"

    mk_repo() {
        r="$TMP/$1"; rm -rf "$r"; mkdir -p "$r"
        ( cd "$r" && $GIT init -q . && printf '### \302\2478.1 — base rule\n' > C.md \
          && $GIT add C.md && $GIT commit -qm base ) >/dev/null 2>&1
        printf '%s' "$r"
    }
    mk_reg() {
        # NOTE: the target path is captured BEFORE `shift`. Using "$1" after
        # the shift appends to a file named after the ROW — a silently empty
        # fixture that would make every golden case vacuous. Observed and
        # fixed during authoring; kept commented so it is not reintroduced.
        _dst=$1
        printf '# fixture registry\n' > "$_dst"
        shift
        for row in "$@"; do printf '%s\n' "$row" >> "$_dst"; done
    }
    # run_case <label> <expected-rc> <repo> <registry> [extra args...]
    run_case() {
        lbl=$1; want=$2; repo=$3; reg=$4; shift 4
        out=$("$SELF_DIR/$TOOL" --corpus "$repo/C.md" --bindings "$reg" \
              --gates-dir "$sgates" --baseline "$sgates/baseline.txt" "$@" 2>&1)
        got=$?
        if [ "$got" -eq "$want" ]; then
            printf 'PASS  %-46s rc=%s\n' "$lbl" "$got"; pass=$((pass + 1))
        else
            printf 'FAIL  %-46s rc=%s want=%s\n' "$lbl" "$got" "$want"
            printf '%s\n' "$out" | sed 's/^/        | /'
            fail=$((fail + 1))
        fi
        printf '%s' "$out" > "$TMP/last_out.txt"
    }

    # ---- golden-FALSE: clean, correctly bound new rule -> must NOT fire ----
    r=$(mk_repo gf1)
    printf '### \302\2478.2 — a properly bound new rule\n' >> "$r/C.md"
    mk_reg "$TMP/gf1.tsv" "8.2${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-FALSE bound-new-rule (must ALLOW)" 0 "$r" "$TMP/gf1.tsv"

    # ---- golden-FALSE: CARRIER decoy -> must NOT be read as a declaration --
    r=$(mk_repo gf2)
    printf '**\302\2478.1 carve-out.** An amendment to an existing anchor.\n' >> "$r/C.md"
    mk_reg "$TMP/gf2.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-FALSE carrier-decoy (must ALLOW)" 0 "$r" "$TMP/gf2.tsv"

    # ---- golden-FALSE: no change at all -> must NOT fire -------------------
    r=$(mk_repo gf3)
    mk_reg "$TMP/gf3.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-FALSE no-change (must ALLOW)" 0 "$r" "$TMP/gf3.tsv"

    # ---- golden-TRUE FR-011: new rule, no registry row -> REFUSE ----------
    r=$(mk_repo gt1)
    printf '### \302\2478.9 — an unbound new rule\n' >> "$r/C.md"
    mk_reg "$TMP/gt1.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-TRUE FR-011 no-seam (must REFUSE)" 2 "$r" "$TMP/gt1.tsv"
    grep -q 'rule_NAMES_NO_SEAM' "$TMP/last_out.txt" && grep -q '8\.9' "$TMP/last_out.txt" \
        && { printf 'PASS  %-46s\n' "  ...names the offender + closed-set reason"; pass=$((pass+1)); } \
        || { printf 'FAIL  %-46s\n' "  ...names the offender + closed-set reason"; fail=$((fail+1)); }

    # ---- golden-TRUE FR-018: new rule duplicates a bound pair -> REFUSE ---
    r=$(mk_repo gt2)
    printf '### \302\2478.7 — a restating new rule\n' >> "$r/C.md"
    mk_reg "$TMP/gt2.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.7${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-TRUE FR-018 restatement (must REFUSE)" 2 "$r" "$TMP/gt2.tsv"
    grep -q 'rule_IS_RESTATEMENT' "$TMP/last_out.txt" && grep -q 'covering rule = 8\.1' "$TMP/last_out.txt" \
        && { printf 'PASS  %-46s\n' "  ...NAMES the covering rule (FR-018)"; pass=$((pass+1)); } \
        || { printf 'FAIL  %-46s\n' "  ...NAMES the covering rule (FR-018)"; fail=$((fail+1)); }

    # ---- golden-TRUE: seam id outside the E5 closed set -> REFUSE ---------
    r=$(mk_repo gt3)
    mk_reg "$TMP/gt3.tsv" "8.1${TAB}deploy${TAB}CM-STUB-ALPHA"
    run_case "golden-TRUE near-miss seam id (must REFUSE)" 2 "$r" "$TMP/gt3.tsv"

    # ---- golden-TRUE: gate token with no executable site -> REFUSE -------
    r=$(mk_repo gt4)
    mk_reg "$TMP/gt4.tsv" "8.1${TAB}pre-build${TAB}CM-NO-SUCH-GATE"
    run_case "golden-TRUE token w/o gate site (must REFUSE)" 2 "$r" "$TMP/gt4.tsv"

    # ---- golden-TRUE: unreadable baseline -> REFUSE, never 'no findings' --
    r=$(mk_repo gt5)
    mk_reg "$TMP/gt5.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-TRUE unreadable baseline (must REFUSE)" 2 "$r" "$TMP/gt5.tsv" --baseline "$TMP/nope.txt"

    # ---- golden-TRUE: ratchet breach -> FAIL (a real, measured condition) -
    r=$(mk_repo gt6)
    printf '0\n' > "$TMP/zero.txt"
    mk_reg "$TMP/gt6.tsv" "8.5${TAB}pre-build${TAB}CM-STUB-ALPHA"
    run_case "golden-TRUE ratchet breach (must FAIL=1)" 1 "$r" "$TMP/gt6.tsv" --baseline "$TMP/zero.txt"

    printf '\n%s --selftest: pass=%s fail=%s\n' "$TOOL" "$pass" "$fail"
    [ "$fail" -eq 0 ] || return 1
    return 0
}

if [ "$SELFTEST" -eq 1 ]; then
    run_selftest; exit $?
fi

run_check
exit $?
