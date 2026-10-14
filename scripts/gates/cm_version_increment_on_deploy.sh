#!/usr/bin/env bash
# cm_version_increment_on_deploy.sh — CM-VERSION-INCREMENT-ON-DEPLOY gate
# (§11.4.235(B)) + CM-VERSION-DECIMAL-CARRY check (§11.4.235(E.5)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.235(B) mandates: the moment image(s)/artifact(s) deploy, the version
# id is INCREMENTED — every deployed artifact carries a DISTINCT, monotonic,
# greppable id (§11.4.151/§11.4.108/§11.4.200). "Two deployments sharing one
# version id defeats per-deploy artifact identity → §11.4.235(B) violation."
#
# This gate FAILs when a NEW-artifact deploy shares a version id with a prior
# deploy — i.e. when the deploy ledger records ONE version id against TWO OR
# MORE DISTINCT artifact fingerprints. A re-deploy of the IDENTICAL artifact
# (same fingerprint) under the same version id is NOT a new-artifact deploy
# and is the §11.4.201(1) NEGATIVE-CONTROL that MUST PASS (never a false
# positive).
#
# ── Consumer binding (§11.4.28 / §11.4.35 — DATA, not engine code) ────────────
# Project-agnostic engine. The consuming project supplies a key=value config
# (path via --config <file> or $CM_VERSION_DEPLOY_CONFIG) declaring ONLY the
# keys below. Round 4 (2026-10-09, STRUCTURAL) replaced the ad-hoc key greps
# with ONE strict parser: every non-blank, non-`#` line MUST be `key = value`
# with a key from this list and a non-empty value — an unknown key (a
# `deploy_leger` typo), a non key=value line, an empty value, or a duplicated
# key is a config error (exit 2), never a silent unbind:
#
#   deploy_ledger = <path>   # append-only TSV; one row per deploy:
#                            #   <version_id>\t<artifact_fingerprint>
#                            # `#`-comment + blank lines ignored.
#   version_scheme = <s>     # REQUIRED whenever deploy_ledger is bound (fix
#                            #   round 3, 2026-10-09): closed set
#                            #   positional-digit | semver | calver | other.
#                            #   ONLY `positional-digit` arms the
#                            #   CM-VERSION-DECIMAL-CARRY check; semver /
#                            #   calver / other are exempt ONLY by this
#                            #   explicit declaration PLUS scheme_decision_ref.
#                            #   Bound ledger + no declaration -> UNDECLARED
#                            #   (exit 3), never a silent skip. A value outside
#                            #   the set -> exit 2.
#   scheme_decision_ref = <r> # REQUIRED with semver / calver / other (round 4,
#                            #   §11.4.235(E.5)): a reference to the recorded
#                            #   operator decision (§11.4.66) naming this
#                            #   consumer's exemption. Absent -> UNDECLARED
#                            #   (exit 3). The gate checks only that the
#                            #   reference is declared; whether the decision
#                            #   record exists and says so is a review
#                            #   obligation the gate cannot verify (§11.4.6).
#   carry_adoption_marker = <line>  # OPTIONAL; the carry check binds only the
#                            #   ledger rows AFTER the first ledger line whose
#                            #   whitespace-trimmed text equals <line> exactly
#                            #   (the §11.4.224(E) adoption fence). The marker
#                            #   line itself is the fence and is EXCLUSIVE — it
#                            #   is never carry-checked, even when it happens to
#                            #   be a data row. Declared but absent from the
#                            #   ledger -> exit 2 (config error, never a silent
#                            #   pass) whatever the scheme. Match is EXACT on the
#                            #   trimmed line (a line merely containing the text
#                            #   is not the fence). Declared, present, and no
#                            #   data row after it -> CARRY: SKIP (an empty set is
#                            #   never a carry PASS). Unset -> every row binds.
#
# The ledger path resolves relative to the config file's directory when not
# absolute. NO config named at all (neither --config nor the env var) ⇒ honest
# SKIP (§11.4.3) — feature_disabled_by_config. A config that IS named but is
# missing, not a regular file, or unreadable ⇒ config error (exit 2), never a
# SKIP. deploy_ledger unset ⇒ honest SKIP (nothing bound) — legitimate ONLY for
# a consumer NOT bound by §11.4.235(E.4); for an (E.4)-bound consumer the
# release seam MUST treat this SKIP as a config error (the gate cannot know
# which kind of consumer called it). A bound ledger whose file is absent ⇒
# honest SKIP — topology_unsupported — PROVIDED the scheme is properly
# declared; a ledger path that exists but is a directory or unreadable ⇒
# exit 2. NEVER a fake pass (§11.4.6).
#
# LEDGER ROWS (round 4, strict): every non-blank, non-`#` ledger line MUST be
# EXACTLY two non-empty TAB-separated fields <version_id>\t<fingerprint>
# (surrounding whitespace of each field trimmed). A space-separated row, a
# third field, an empty id or an empty fingerprint is a config error (exit 2),
# never reinterpreted. The one exception is the adoption-marker line itself,
# which is a fence and may be any text.
#
# CARRY GRAMMAR (round 4, §11.4.235(E.5)) — the POSITIONAL-DIGIT ID GRAMMAR,
# implemented identically by the consumer's version tool:
#   (i)   in EVERY dotted numeric group of the id (any run of >= 2 dot-joined
#         decimal positions, not only the owned one), each non-leftmost
#         position is a single digit 0..9 and the leftmost has no leading zero;
#   (ii)  no two numeric runs are joined by a single dash ("0.0-9",
#         "0.0.1-1") — that makes the owned group ambiguous;
#   (iii) the OWNED group — the dot-joined positions that END the id after its
#         last dash, or the whole id when it has no dash — has no leading zero
#         in any position (a single-position owned group "-dev-7" may grow).
# An id ending in a non-numeric suffix ("-rc1") has no owned group and is
# checked by (i) and (ii) alone; opaque ids with no dotted group and no dash
# (v1, v10) are outside the rule (§11.4.201(1) false-positive guard).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_version_increment_on_deploy.sh [--config <file>]
#   cm_version_increment_on_deploy.sh --print-example-config   # ALONE only
#   cm_version_increment_on_deploy.sh -h | --help              # ALONE only
#   The two informational modes exit 0 WITHOUT a VERDICT line (they are not a
#   gate run); combined with any other argument they are a config error.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Resolved-ledger evidence (§11.4.201(5)), human-readable lines, and TWO
#   machine-readable lines that callers MUST parse. The exit code alone is
#   ambiguous BY DESIGN — exit 0 covers CARRY PASS and CARRY SKIP, exit 1
#   covers a version-id collision and a carry failure — so a caller that reads
#   only the exit code cannot tell which check passed or failed:
#     VERDICT: PASS | FAIL | SKIP | UNDECLARED | ERROR
#     CARRY:   PASS | FAIL | SKIP | NOT_EVALUATED
#   On FAIL, names the offending version id + its distinct fingerprints, or
#   the offending carry position.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). No network/commit/device mutation.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash + awk + grep + sed. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.235(B)/(E.5), §11.4.151/§11.4.108/§11.4.200 (per-deploy artifact
#   identity), §11.4.201(1)/(5) (negative-control + resolved evidence),
#   §11.4.3 (SKIP), §11.4.135 (absence blocks at the release seam),
#   §11.4.28/§11.4.35 (decoupled engine + consumer DATA), §11.4.6 (no fake
#   pass), §1.1 (paired mutation: cm_version_increment_on_deploy_mutation_test.sh).
#
# ── Exit codes (fix round 3, 2026-10-09 — every verdict has its OWN code) ────
#   0 — PASS: every version id maps to one artifact (and, when armed, every
#       in-scope id obeys the decimal carry).
#   1 — FAIL: >= 1 version id shared by >= 2 distinct artifact fingerprints,
#       OR an in-scope id has a non-leftmost carry position that is not a
#       single digit 0..9 (CM-VERSION-DECIMAL-CARRY, §11.4.235(E.5)).
#   2 — config / argument error (unknown arg, informational mode not alone,
#       named config missing/unreadable/not a file, unknown or duplicated or
#       empty config key, non key=value config line, scheme outside the closed
#       set, ledger path not a regular file or unreadable, malformed ledger
#       row, declared marker absent from the ledger). Takes precedence over
#       every other result.
#   3 — UNDECLARED: deploy_ledger is bound but version_scheme is not declared,
#       or a non-positional scheme is declared without scheme_decision_ref. A
#       release seam consuming this gate MUST treat 3 as blocking, exactly as
#       a FAIL (§11.4.135); no release seam consumes the gate yet, so today
#       that is an obligation on the seam, tracked by each consuming project
#       (§11.4.197), not an enforced block. Exit 1 takes precedence when a
#       version-id collision is also present.
#   4 — SKIP: honest, nothing to enforce (no config named, ledger unbound, or
#       a properly declared scheme with no recorded deploys). NOT a PASS — a
#       caller that maps 4 to success has turned an absence into a pass.
#
# Classification: universal (§11.4.17) — no project-specific data in the engine.

set -euo pipefail
export LC_ALL=C   # byte semantics for every [0-9] class below

GATE="CM-VERSION-INCREMENT-ON-DEPLOY"

verdict() { # verdict <VERDICT> <CARRY> <exit>
    echo "VERDICT: $1"
    echo "CARRY: $2"
    exit "$3"
}
cfg_error() { echo "${GATE}: $*" >&2; verdict ERROR NOT_EVALUATED 2; }

# The header comment block (line 2 up to the first non-comment line), never code.
print_help() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

if [ $# -ge 1 ]; then
    case "$1" in
        -h|--help|--print-example-config)
            [ $# -eq 1 ] || cfg_error "'$1' is an informational mode and must be the only argument (got: $*)"  # GATE_INFO_ALONE
            if [ "$1" = "--print-example-config" ]; then
                cat <<'EOF'
# CM-VERSION-INCREMENT-ON-DEPLOY marker-binding config (consumer DATA, §11.4.35).
# deploy_ledger : append-only TSV, one row per deploy: <version_id>\t<artifact_fingerprint>
deploy_ledger = deploys.tsv
# version_scheme : REQUIRED once deploy_ledger is bound.
#   positional-digit | semver | calver | other (only positional-digit arms the carry check)
version_scheme = positional-digit
# scheme_decision_ref : REQUIRED with semver / calver / other — the recorded operator decision.
# scheme_decision_ref = <decision record reference>
# carry_adoption_marker : rows after this exact ledger line are carry-checked
# carry_adoption_marker = # decimal-carry adopted
EOF
            else
                print_help
            fi
            exit 0 ;;
    esac
fi

config=""; config_src=""
if [ -n "${CM_VERSION_DEPLOY_CONFIG:-}" ]; then config="$CM_VERSION_DEPLOY_CONFIG"; config_src="\$CM_VERSION_DEPLOY_CONFIG"; fi
while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            [ $# -ge 2 ] && [ -n "$2" ] || cfg_error "--config needs a non-empty value"
            config="$2"; config_src="--config"; shift 2 ;;
        *) cfg_error "unknown arg '$1'" ;;
    esac
done

if [ -z "$config" ]; then
    echo "⏭ ${GATE}: SKIP — feature_disabled_by_config: no consumer deploy-ledger binding"
    echo "   (supply --config <file> or \$CM_VERSION_DEPLOY_CONFIG; see --print-example-config)"
    verdict SKIP NOT_EVALUATED 4
fi
# A config that is NAMED but cannot be read is an error, never a SKIP (round 4, M-1).
[ -e "$config" ] || cfg_error "config '${config}' (from ${config_src}) does not exist"   # GATE_CONF_EXISTS
[ -f "$config" ] || cfg_error "config '${config}' (from ${config_src}) is not a regular file"   # GATE_CONF_REGULAR
[ -r "$config" ] || cfg_error "config '${config}' (from ${config_src}) is not readable"   # GATE_CONF_READABLE

config_dir="$(cd "$(dirname "$config")" && pwd)"

# ONE strict config parser (round 4, STRUCTURAL — replaces the per-key greps):
# allowed keys only, exactly once each, non-empty values, nothing else.
parsed="$(awk '
    BEGIN { allowed["deploy_ledger"]; allowed["version_scheme"]; allowed["scheme_decision_ref"]; allowed["carry_adoption_marker"] }
    /^[[:space:]]*#/ { next }   # GATE_CONF_COMMENT_SKIP
    {
        t = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
        if (t == "") next
        if (t !~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) { printf "line %d is not `key = value`: %s\n", NR, t; exit 3 }
        k = t; sub(/[[:space:]]*=.*$/, "", k)
        v = t; sub(/^[^=]*=/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (!(k in allowed)) { printf "line %d: unknown key `%s` (allowed: deploy_ledger, version_scheme, scheme_decision_ref, carry_adoption_marker)\n", NR, k; exit 3 }   # GATE_CONF_UNKNOWN_KEY
        if (k in seen) { printf "line %d: key `%s` already declared on line %d — never a silent first/last pick\n", NR, k, seen[k]; exit 3 }   # GATE_CONF_DUP_KEY
        if (v == "") { printf "line %d: key `%s` has an empty value\n", NR, k; exit 3 }   # GATE_CONF_EMPTY_VALUE
        seen[k] = NR; printf "%s\t%s\n", k, v
    }' "$config")" || cfg_error "config ${config}: ${parsed:-unparseable} (config error, §11.4.6)"

ledger_val=""; scheme=""; decision_ref=""; marker=""
while IFS=$'\t' read -r k v; do
    case "$k" in
        deploy_ledger) ledger_val="$v" ;;
        version_scheme) scheme="$v" ;;
        scheme_decision_ref) decision_ref="$v" ;;
        carry_adoption_marker) marker="$v" ;;
    esac
done <<<"$parsed"

case "$scheme" in
    ""|positional-digit|semver|calver|other) ;;
    *) cfg_error "version_scheme '${scheme}' is outside the closed set {positional-digit, semver, calver, other} (config error, §11.4.6 — never a silent skip)" ;;
esac

case "$ledger_val" in
    "") echo "⏭ ${GATE}: SKIP — feature_disabled_by_config: deploy_ledger unset (nothing bound; a release seam MUST treat this as a config error for a consumer bound by §11.4.235(E.4))"
        verdict SKIP NOT_EVALUATED 4 ;;
    /*) ledger="$ledger_val" ;;
    *)  ledger="${config_dir}/${ledger_val}" ;;
esac

# Once a ledger is bound the scheme MUST be declared, and an exemption from the
# carry MUST cite its recorded operator decision (round 4, M-9).
undeclared=""
if [ -z "$scheme" ]; then
    undeclared="deploy_ledger is bound but version_scheme is not declared"   # GATE_UNDECLARED_GUARD
elif [ "$scheme" != "positional-digit" ] && [ -z "$decision_ref" ]; then
    undeclared="version_scheme=${scheme} claims the carry exemption without scheme_decision_ref (the recorded operator decision, §11.4.66)"   # GATE_DECISION_REF_GUARD
fi

if [ ! -e "$ledger" ]; then
    if [ -n "$undeclared" ]; then
        echo "⛔ ${GATE}: UNDECLARED — ${undeclared} (ledger ${ledger}; §11.4.235(E.5))"
        verdict UNDECLARED NOT_EVALUATED 3
    fi
    echo "⏭ ${GATE}: SKIP — topology_unsupported: deploy_ledger file absent (${ledger})"
    verdict SKIP NOT_EVALUATED 4
fi
[ -f "$ledger" ] || cfg_error "deploy_ledger '${ledger}' is not a regular file"   # GATE_LEDGER_REGULAR
[ -r "$ledger" ] || cfg_error "deploy_ledger '${ledger}' is not readable"

# ONE strict ledger parser (round 4, STRUCTURAL): emits
#   M                                   the adoption-marker line (first exact match)
#   R<TAB>id<TAB>fp<TAB>line<TAB>ismark one record per data row
# and refuses any malformed row. Both checks below consume ONLY these records.
records="$(awk -v marker="$marker" '
    {
        raw = $0; t = raw; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
        ismark = 0
        if (marker != "" && !fenced && t == marker) { fenced = 1; ismark = 1; print "M" }   # GATE_MARKER_EXACT
        if (t == "" || t ~ /^#/) next   # GATE_LEDGER_COMMENT_SKIP
        n = split(raw, f, "\t")
        id = f[1]; fp = f[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", id); gsub(/^[[:space:]]+|[[:space:]]+$/, "", fp)
        if (n != 2 || id == "" || fp == "") {   # GATE_LEDGER_ROW_SHAPE
            if (ismark) next
            printf "line %d is not exactly two non-empty TAB-separated fields <version_id>\\t<fingerprint> (found %d field(s)): %s\n", NR, n, t
            exit 3
        }
        printf "R\t%s\t%s\t%d\t%d\n", id, fp, NR, ismark
    }' "$ledger")" || cfg_error "deploy_ledger ${ledger}: ${records:-unparseable} (malformed row — never reinterpreted, §11.4.6)"

data_rows="$(printf '%s\n' "$records" | awk -F'\t' '$1 == "R" { n++ } END { print n + 0 }')"
marker_seen="$(printf '%s\n' "$records" | awk '$0 == "M" { f = 1 } END { print f + 0 }')"

echo "${GATE}: deploy_ledger = ${ledger}  [data rows: ${data_rows}]  version_scheme=${scheme:-<undeclared>}  (§11.4.201(5) evidence)"

# Detect any version id bound to >1 DISTINCT artifact fingerprint.
report="$(printf '%s\n' "$records" | awk -F'\t' '
    $1 != "R" { next }
    {
        v = $2; fp = $3; key = v SUBSEP fp
        if (!(key in seen)) { seen[key] = 1; cnt[v]++; lst[v] = lst[v] (lst[v] == "" ? "" : ", ") fp }
    }
    END {
        bad = 0
        for (v in cnt) { if (cnt[v] > 1) { printf "OFFENDER version_id=%s distinct_fingerprints=[%s]\n", v, lst[v]; bad = 1 } }
        exit bad
    }')" && awk_rc=0 || awk_rc=$?

if [ "$awk_rc" -eq 1 ]; then
    echo "$report"
    echo "❌ ${GATE}: FAIL — a version id is shared by ≥2 distinct deployed artifacts (§11.4.235(B))"
    verdict FAIL NOT_EVALUATED 1
fi

if [ -n "$undeclared" ]; then
    echo "⛔ ${GATE}: UNDECLARED — ${undeclared}; the carry rule cannot be scoped (§11.4.235(E.5); a consuming release seam MUST block on this, §11.4.135)"
    verdict UNDECLARED NOT_EVALUATED 3
fi

if [ -n "$marker" ] && [ "$marker_seen" -ne 1 ]; then   # GATE_MARKER_PRESENT
    cfg_error "carry_adoption_marker '${marker}' is declared but absent from ${ledger} (config error — never a silent pass, §11.4.6)"
fi

if [ "${data_rows:-0}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no deploys recorded in the ledger"
    verdict SKIP NOT_EVALUATED 4
fi

# ── CM-VERSION-DECIMAL-CARRY (§11.4.235(E.5)) ──────────────────────────────
# Armed ONLY for a declared `version_scheme = positional-digit`; binds only the
# data rows AFTER the declared adoption marker (the marker line itself is the
# exclusive fence). The grammar (i)-(iii) is documented in the header and is
# the same one the consumer's version tool enforces.
if [ "$scheme" != "positional-digit" ]; then
    echo "✅ ${GATE}: PASS — every deployed artifact carries a distinct version id (§11.4.235(B))"
    echo "⏭ CM-VERSION-DECIMAL-CARRY: SKIP — feature_disabled_by_config: declared version_scheme=${scheme} is exempt by recorded decision '${decision_ref}' (the carry binds only a declared positional-digit scheme, §11.4.235(E.5))"
    verdict PASS SKIP 0
fi
echo "CM-VERSION-DECIMAL-CARRY: version_scheme=positional-digit  carry_adoption_marker=${marker:-<unset: every row binds>}  (§11.4.201(5) evidence)"

in_scope="$(printf '%s\n' "$records" | awk -F'\t' -v fence="$marker" '
    BEGIN { adopted = (fence == "") }
    $0 == "M" { adopted = 1; next }
    $1 == "R" && adopted && $5 == 0 { print $2 }')"   # GATE_CARRY_SCOPE

if [ -z "$in_scope" ]; then
    echo "✅ ${GATE}: PASS — every deployed artifact carries a distinct version id (§11.4.235(B))"
    echo "⏭ CM-VERSION-DECIMAL-CARRY: SKIP — no deploy row after the adoption marker yet (an empty set is never a carry PASS)"
    verdict PASS SKIP 0
fi

carry_report="$(printf '%s\n' "$in_scope" | awk '
    function offend(msg) { printf "OFFENDER version_id=%s %s\n", v, msg; bad = 1 }
    {
        v = $0
        if (v ~ /[0-9]-[0-9]/) { offend("(ii) two numeric runs are joined by a single dash — the owned group is ambiguous"); next }   # GATE_DASHJOIN
        rest = v
        while (match(rest, /[0-9]+(\.[0-9]+)+/)) {   # GATE_EVERY_GROUP
            grp = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
            n = split(grp, p, ".")
            if (p[1] ~ /^0[0-9]/) { offend("(i) group " grp ": leftmost position " p[1] " has a leading zero"); next }   # GATE_LEFT_LEADZERO
            for (i = 2; i <= n; i++) if (length(p[i]) != 1) { offend("(i) group " grp ": position " i " value " p[i] " — a non-leftmost position must be a single digit 0..9"); next }   # GATE_NONLEFT_DIGIT
        }
        if (match(v, /(^|-)[0-9]+(\.[0-9]+)*$/)) {   # GATE_OWNED_GROUP
            og = substr(v, RSTART, RLENGTH); sub(/^-/, "", og)
            n = split(og, p, ".")
            for (i = 1; i <= n; i++) if (p[i] ~ /^0[0-9]/) { offend("(iii) owned group " og ": position " i " value " p[i] " has a leading zero"); next }
        }
    }
    END { exit bad + 0 }')" && carry_rc=0 || carry_rc=$?

if [ "$carry_rc" -eq 1 ]; then
    echo "$carry_report"
    echo "✅ ${GATE}: PASS — every deployed artifact carries a distinct version id (§11.4.235(B))"
    echo "❌ CM-VERSION-DECIMAL-CARRY: FAIL — a version id violates the positional-digit id grammar (§11.4.235(E.5))"
    verdict FAIL FAIL 1
fi

echo "✅ ${GATE}: PASS — every deployed artifact carries a distinct version id (§11.4.235(B))"
echo "✅ CM-VERSION-DECIMAL-CARRY: PASS — every in-scope version id obeys the positional-digit id grammar (§11.4.235(E.5))"
verdict PASS PASS 0
