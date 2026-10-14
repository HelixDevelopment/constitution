#!/usr/bin/env bash
# cm_version_increment_on_deploy_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-VERSION-INCREMENT-ON-DEPLOY (§11.4.235(B)) + its
# CM-VERSION-DECIMAL-CARRY check (§11.4.235(E.5)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuine with the §11.4.107(10) golden-good / golden-bad /
# negative-control set. Builds disposable deploy-ledger fixtures + configs:
#   BAD      : two DISTINCT artifact fingerprints share ONE version id
#              -> gate MUST FAIL (§11.4.235(B) — two deploys, one version id).
#   GOOD     : distinct version id per distinct artifact -> gate MUST PASS.
#   NEG-CTRL : the SAME artifact (identical fingerprint) re-deployed under the
#              SAME version id -> NOT a new-artifact deploy -> gate MUST PASS
#              (§11.4.201(1) false-positive guard).
#   SKIP-EMPTY / SKIP-NOCONF / SKIP-UNBOUND : nothing to enforce -> honest
#              SKIP with its OWN exit code 4 and `VERDICT: SKIP` (fix round 3:
#              a SKIP is never reported as a PASS-shaped exit 0).
#   UNDECLARED / UNDECLARED-LEDGER-ABSENT : a deploy ledger is bound but no
#              version_scheme is declared -> blocking exit 3, `VERDICT:
#              UNDECLARED` (was NEG-CTRL-NOSCHEME, which wrongly passed).
#   BAD-CARRY / BAD-CARRY-MID / -NONLAST-ROW / -2POS / -LEADZERO / -4POS /
#   -SUFFIX / -POSTMARKER / -PADDED-MARKER : a non-leftmost position of the
#              LAST dotted numeric group is not a single digit 0..9 -> exit
#              EXACTLY 1 (not merely non-zero) with `CARRY: FAIL`.
#   GOOD-CARRY / NEG-CTRL-LEFTMOST / -NONDOTTED / -SUFFIX / -SEMVER /
#   -PREMARKER / -DATAROW-MARKER / -POSTMARKER-COMMENT : must PASS with the
#              exact CARRY verdict (PASS or SKIP) — §11.4.201(1) guards.
#   MARKER-ABSENT / BAD-SCHEME / DUP-KEY : config error -> exit 2, `VERDICT:
#              ERROR`.
#   Round 4 (2026-10-09, STRUCTURAL — the gate's config + ledger parsing was
#   REPLACED by one strict parser, and the carry check by the shared
#   POSITIONAL-DIGIT ID GRAMMAR the version tool also implements):
#   - grammar (i) every dotted group, (ii) no dash-joined numeric runs,
#     (iii) the owned group has no leading zero: BAD-CARRY-DOTTED-SUFFIX,
#     -BUILD-META, -PREFIX-GROUP, -LEFT-LEADZERO, -DASHJOIN, -DASHJOIN-HIST,
#     -OWNED-LEADZERO; NEG-CTRL-DOTTED-SUFFIX / -SINGLE-OWNED / -FP-DOTTED;
#   - strict ledger rows (exactly 2 non-empty TAB fields): LEDGER-NOTAB,
#     -3FIELDS, -EMPTY-FP, -EMPTY-ID -> exit 2;
#   - config-file errors: CONF-MISSING, -DIR, -UNREADABLE, -ENV-MISSING,
#     -UNKNOWN-KEY, -NOT-KV, -EMPTY-VALUE, LEDGER-IS-DIR, DUP-LEDGER-KEY,
#     DUP-MARKER-KEY -> exit 2;
#   - marker scope: MARKER-NO-ROWS-AFTER (CARRY SKIP), MARKER-ABSENT-SEMVER
#     (exit 2 whatever the scheme), NEG-CTRL-MARKER-SUPERSTRING (exact match);
#   - exemption record: UNDECLARED-NO-DECISION-REF (non-positional scheme
#     without scheme_decision_ref -> exit 3);
#   - CLI: HELP-HEADER-ONLY, HELP-NOT-ALONE, EXAMPLE-NO-VERDICT,
#     EXAMPLE-NOT-ALONE, EXAMPLE-THROUGH-GATE (the documented example config
#     is itself a valid config).
#   Every case asserts the exact exit code AND both machine-readable lines
#   (VERDICT / CARRY); round-3 rows name the reviewer mutant they kill
#   (M1 M2 M3 M4 M6 M7 M8 M9; M5 is recorded as near-equivalent).
# The pair only proves the gate genuine if it FAILs on the collision AND
# PASSes on distinct-ids AND the identical-redeploy negative-control AND the
# honest-SKIP paths (the §1.1 discriminator + §11.4.201(1) false-positive
# guard).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_version_increment_on_deploy_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir (trap-cleaned). No network/commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_version_increment_on_deploy.sh. bash -n clean.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1, §11.4.235(B), §11.4.201(1) (false-positive guard), §11.4.107(10)
#   (golden-good/bad/negative-control), §11.4.3 (SKIP-with-reason).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every fixture produced its exact required exit code and verdict lines.
#   1 — a discriminator case did not behave as required.
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_version_increment_on_deploy.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cmvid_mut.XXXXXX")"
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }

# $1=name  $2..=ledger rows (each "version_id<TAB>fingerprint"); writes config+ledger, echoes config path.
# Extra config lines come from $EXTRA_CONF (newline-separated), e.g. the
# version_scheme / carry_adoption_marker keys of the (E.5) scope fence.
mkfix() {
    local name="$1"; shift
    local d="$TMP/$name"; mkdir -p "$d"
    echo "deploy_ledger = deploys.tsv" > "$d/config"
    [ -n "${EXTRA_CONF:-}" ] && printf '%s\n' "$EXTRA_CONF" >> "$d/config"
    : > "$d/deploys.tsv"
    local row
    for row in "$@"; do printf '%s\n' "$row" >> "$d/deploys.tsv"; done
    echo "$d/config"
}
TAB=$'\t'
PD="version_scheme = positional-digit"

# expect_v <rc> <VERDICT> <CARRY> <desc> <cmd...> — exact exit code AND the two
# machine-readable verdict lines (fix round 3: every verdict has its own exit
# code and callers parse `VERDICT:` / `CARRY:`, so a SKIP can never pass as PASS).
expect_v() { local want="$1" wv="$2" wc="$3" desc="$4"; shift 4; local got=0 out
    out="$("$@" 2>/dev/null)" || got=$?
    if [ "$got" -eq "$want" ] && grep -qx "VERDICT: ${wv}" <<<"$out" && grep -qx "CARRY: ${wc}" <<<"$out"; then
        note "✅ META OK:   ${desc} — exit ${got}, VERDICT ${wv}, CARRY ${wc}"
    else
        note "❌ META FAIL: ${desc} — exit ${got} (required ${want}); verdict lines: $(grep -E '^(VERDICT|CARRY): ' <<<"$out" | tr '\n' ' ')(required VERDICT ${wv} / CARRY ${wc})"; rc=1
    fi; }

# expect_info <desc> <cmd...> — an informational mode (--help /
# --print-example-config used ALONE): exit 0 and NO `VERDICT:` line, so no caller
# can read it as a gate verdict.
expect_info() { local desc="$1"; shift; local got=0 out
    out="$("$@" 2>/dev/null)" || got=$?
    if [ "$got" -eq 0 ] && ! grep -q '^VERDICT: ' <<<"$out" && [ -n "$out" ]; then
        note "✅ META OK:   ${desc} — exit 0, no VERDICT line"
    else
        note "❌ META FAIL: ${desc} — exit ${got}; VERDICT line present or empty output"; rc=1
    fi; }

# expect_msg <rc> <stderr-substring> <desc> <cmd...> — exact exit code AND the
# gate's OWN reason on stderr (distinguishes two refusal paths that share exit 2).
expect_msg() { local want="$1" sub="$2" desc="$3"; shift 3; local got=0 err
    err="$("$@" 2>&1 >/dev/null)" || got=$?
    case "$err" in *"$sub"*) local hit=1 ;; *) local hit=0 ;; esac
    if [ "$got" -eq "$want" ] && [ "$hit" -eq 1 ]; then note "✅ META OK:   ${desc} — exit ${got}, reason '${sub}'"
    else note "❌ META FAIL: ${desc} — exit ${got} (required ${want}); stderr lacks '${sub}'"; rc=1; fi; }

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-VERSION-INCREMENT-ON-DEPLOY"
echo "fixtures under: $TMP"
echo "======================================================================"

REF="scheme_decision_ref = OPD-EXAMPLE-0001"
OTHER="version_scheme = other
${REF}"
expect_v 1 FAIL NOT_EVALUATED "BAD (two distinct artifacts share version_id v1; no scheme declared — the collision FAIL takes precedence over UNDECLARED)" \
    bash "$GATE" --config "$(mkfix bad "v1${TAB}fpA" "v1${TAB}fpB")"

expect_v 0 PASS SKIP "GOOD (distinct version id per distinct artifact; declared scheme 'other' is carry-exempt)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix good "v1${TAB}fpA" "v2${TAB}fpB")"

expect_v 0 PASS SKIP "NEG-CTRL (same artifact re-deployed under same version id — §11.4.201(1) false-positive guard)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix neg "v1${TAB}fpA" "v1${TAB}fpA")"

expect_v 4 SKIP NOT_EVALUATED "SKIP-EMPTY (declared scheme, ledger with only a comment/blank row -> honest topology SKIP, distinct exit 4)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix skipempty "# header only" "")"

expect_v 4 SKIP NOT_EVALUATED "SKIP-NOCONF (no --config at all -> honest feature_disabled_by_config SKIP, distinct exit 4)" \
    env -u CM_VERSION_DEPLOY_CONFIG bash "$GATE"

mkdir -p "$TMP/unbound"; printf '%s\n' "# no ledger bound" "$PD" > "$TMP/unbound/config"
expect_v 4 SKIP NOT_EVALUATED "SKIP-UNBOUND (config without a deploy_ledger key -> nothing bound, SKIP not PASS)" \
    bash "$GATE" --config "$TMP/unbound/config"

mkdir -p "$TMP/undeclabsent"; printf '%s\n' "deploy_ledger = missing.tsv" > "$TMP/undeclabsent/config"
expect_v 3 UNDECLARED NOT_EVALUATED "UNDECLARED-LEDGER-ABSENT (ledger bound but its file absent AND no scheme -> UNDECLARED, never a silent SKIP)" \
    bash "$GATE" --config "$TMP/undeclabsent/config"

# ── §11.4.235(E.5) DECIMAL-CARRY discriminators (added 2026-10-09) ──────────
# Every carry fixture below declares the positional-digit scheme (EXTRA_CONF)
# unless it is a scope-fence negative control.
expect_v 1 FAIL FAIL "BAD-CARRY (no-carry successor 1.0.0-dev-0.0.10 — a non-leftmost position exceeds 9)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badcarry "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.0.10${TAB}fpB")"

expect_v 1 FAIL FAIL "BAD-CARRY-MID (middle position 0.12.0 exceeds 9, tag prefix present)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badcarrymid "atmosphere-1.2.1-dev-0.12.0${TAB}fpA")"

expect_v 0 PASS PASS "GOOD-CARRY (1.0.0-dev-0.0.9 -> 1.0.0-dev-0.1.0, decimal carry applied)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix goodcarry "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.1.0${TAB}fpB")"

expect_v 0 PASS PASS "NEG-CTRL-LEFTMOST (leftmost position absorbs the final carry: 9.9.9 -> 10.0.0 — §11.4.201(1) false-positive guard)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negleft "9.9.9${TAB}fpA" "10.0.0${TAB}fpB")"

expect_v 0 PASS PASS "NEG-CTRL-NONDOTTED (opaque ids like v10 carry no dotted group — rule does not apply)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negopaque "v9${TAB}fpA" "v10${TAB}fpB")"

expect_v 1 FAIL FAIL "BAD-CARRY-NONLAST-ROW (offender in a NON-last row, clean last row — kills M_lastrow_only)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badnonlast "1.0.0-dev-0.0.10${TAB}fpA" "1.0.0-dev-0.1.0${TAB}fpB")"

expect_v 1 FAIL FAIL "BAD-CARRY-2POS (2-position group 1.0-dev-0.10 — kills M_three_pos)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix bad2pos "1.0-dev-0.10${TAB}fpA")"

expect_v 1 FAIL FAIL "BAD-CARRY-LEADZERO (leading-zero position 0.05.0 — kills M_numeric)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badlead "0.05.0${TAB}fpA")"

expect_v 1 FAIL FAIL "BAD-CARRY-4POS (4-position id 1.0.0.10 — offender in position 4; kills an only-positions-2-3 mutant, reviewer M6)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix bad4pos "1.0.0.10${TAB}fpA")"

expect_v 1 FAIL FAIL "BAD-CARRY-SUFFIX (1.0.0-dev-0.0.10-rc1 — a suffix never hides the no-carry group; reviewer M8)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badsuffix "1.0.0-dev-0.0.10-rc1${TAB}fpA")"

expect_v 0 PASS PASS "NEG-CTRL-SUFFIX (1.0.0-dev-0.1.0-rc1 — a carried group with a suffix is clean)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negsuffix "1.0.0-dev-0.1.0-rc1${TAB}fpA")"

expect_v 3 UNDECLARED NOT_EVALUATED "UNDECLARED (bound ledger, no version_scheme -> blocking UNDECLARED exit 3, never a silent SKIP; was NEG-CTRL-NOSCHEME)" \
    bash "$GATE" --config "$(mkfix negnoscheme "1.0.0-dev-0.0.10${TAB}fpA")"

expect_v 0 PASS SKIP "NEG-CTRL-SEMVER (version_scheme = semver -> 1.2.10 is correct SemVer, carry SKIPped by explicit declaration)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme = semver
${REF}" mkfix negsemver "1.2.10${TAB}fpA")"

MK="carry_adoption_marker = # decimal-carry adopted"
expect_v 0 PASS PASS "NEG-CTRL-PREMARKER (offender BEFORE the adoption marker is history, clean after)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix negpremark "1.0.0-dev-0.0.10${TAB}fpA" "# decimal-carry adopted" "1.0.0-dev-0.1.0${TAB}fpB")"

expect_v 1 FAIL FAIL "BAD-CARRY-POSTMARKER (offender AFTER the adoption marker)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix badpostmark "1.0.0-dev-0.0.9${TAB}fpA" "# decimal-carry adopted" "1.0.0-dev-0.0.10${TAB}fpB")"

expect_v 0 PASS PASS "NEG-CTRL-DATAROW-MARKER (the marker IS a data row 1.0.0-dev-0.0.10; the fence is exclusive, so the marker row itself is not carry-checked; reviewer M1)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
carry_adoption_marker = 1.0.0-dev-0.0.10" mkfix negdatamark "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.0.10" "1.0.0-dev-0.1.0${TAB}fpB")"

expect_v 0 PASS PASS "NEG-CTRL-POSTMARKER-COMMENT (a comment line after the marker that mentions 1.0.0-dev-0.0.10 is not a row; reviewer M2)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix negpostcomment "1.0.0-dev-0.0.9${TAB}fpA" "# decimal-carry adopted" "# legacy note: 1.0.0-dev-0.0.10 was never deployed" "1.0.0-dev-0.1.0${TAB}fpB")"

expect_v 1 FAIL FAIL "BAD-CARRY-PADDED-MARKER (whitespace-padded marker line, then post-marker row 0.0.11 -> FAIL; reviewer M9)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix badpadmark "1.0.0-dev-0.0.9${TAB}fpA" "   # decimal-carry adopted   " "1.0.0-dev-0.0.11${TAB}fpB")"

expect_v 2 ERROR NOT_EVALUATED "MARKER-ABSENT (declared adoption marker not present in the ledger -> config error, never a silent pass)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix markabsent "1.0.0-dev-0.0.10${TAB}fpA")"

expect_v 2 ERROR NOT_EVALUATED "BAD-SCHEME (version_scheme outside the closed set -> config error, never a silent skip)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme = positonal-digit" mkfix badscheme "1.0.0-dev-0.0.10${TAB}fpA")"

expect_v 2 ERROR NOT_EVALUATED "DUP-KEY (version_scheme declared twice, semver then positional-digit -> config error, never a silent first/last pick; reviewer M4)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme = semver
$PD" mkfix dupkey "1.0.0-dev-0.0.10${TAB}fpA")"


# ── Round 4 (2026-10-09) STRUCTURAL fixtures ────────────────────────────────
# (i) EVERY dotted numeric group is positional, not only the last one (I-4).
expect_v 1 FAIL FAIL "BAD-CARRY-DOTTED-SUFFIX (1.0.0-dev-0.0.10-rc.1.2 — a dotted suffix group no longer hides the no-carry group; reviewer I-4)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix baddotsuf "1.0.0-dev-0.0.10-rc.1.2${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-BUILD-META (1.0.0-dev-0.0.10+build.20261009.3; reviewer I-4)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badbuild "1.0.0-dev-0.0.10+build.20261009.3${TAB}fpA")"
expect_v 0 PASS PASS "NEG-CTRL-DOTTED-SUFFIX (1.0.0-dev-0.1.0-rc.1.2 and +build.20261009.3 — clean groups everywhere)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negdotsuf "1.0.0-dev-0.1.0-rc.1.2${TAB}fpA" "1.0.0-dev-0.1.1+build.20261009.3${TAB}fpB")"
expect_v 1 FAIL FAIL "BAD-CARRY-PREFIX-GROUP (1.2.10-dev-0.0.1 — a non-owned prefix group is positional too)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badprefgrp "1.2.10-dev-0.0.1${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-LEFT-LEADZERO (010.9.9 — leftmost leading zero, the version tool refuses it too)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badleftlz "010.9.9${TAB}fpA")"
# (ii) two numeric runs joined by one dash make the owned group ambiguous (M-4).
expect_v 1 FAIL FAIL "BAD-CARRY-PREFIX-LEADZERO (01.2.1-dev-0.0.9 — leftmost leading zero in a NON-owned group, which only rule (i) can see)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badpreflz "01.2.1-dev-0.0.9${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-DASHJOIN (1.2.1-dev-0.0-10 — dash typo for 0.0.10; reviewer M-4)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix baddash "1.2.1-dev-0.0-10${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-DASHJOIN-FAR (1-2-dev-0.0.9 — rule (ii) applies anywhere in the id, not only at the last dash)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix baddashfar "1-2-dev-0.0.9${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-2POS-PREFIX (1.10-dev-0.0.1 — a two-position non-owned group is a dotted group too)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix bad2pospref "1.10-dev-0.0.1${TAB}fpA")"
expect_v 1 FAIL FAIL "BAD-CARRY-DASHJOIN-HIST (1.0.2-dev-0.0.1-1 — the real pre-adoption tag shape, now refused after the marker)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix baddashhist "1.0.2-dev-0.0.1-1${TAB}fpA")"
# (iii) the owned group has no leading zero in any position.
expect_v 1 FAIL FAIL "BAD-CARRY-OWNED-LEADZERO (1.2.1-dev-07 — single-position owned group with a leading zero)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix badownlz "1.2.1-dev-07${TAB}fpA")"
expect_v 0 PASS PASS "NEG-CTRL-SINGLE-OWNED (1.2.1-dev-7 and 1.2.1-dev-10 — a single-position owned group may grow)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negsingle "1.2.1-dev-7${TAB}fpA" "1.2.1-dev-10${TAB}fpB")"
expect_v 0 PASS PASS "NEG-CTRL-FP-DOTTED (the fingerprint sha-1.0.10 holds a no-carry-shaped number; only the id is carry-checked; reviewer G4)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD" mkfix negfpdot "1.0.0-dev-0.1.0${TAB}sha-1.0.10")"
# strict ledger rows: exactly 2 non-empty TAB-separated fields (I-5 / G10).
expect_v 2 ERROR NOT_EVALUATED "LEDGER-NOTAB (space-separated rows '0.0.9 A' / '0.0.9 B' are malformed, never reinterpreted; reviewer I-5)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix ledgernotab "0.0.9 A" "0.0.9 B")"
expect_v 2 ERROR NOT_EVALUATED "LEDGER-3FIELDS (a third field is malformed)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix ledger3 "v1${TAB}fpA${TAB}extra")"
expect_v 2 ERROR NOT_EVALUATED "LEDGER-EMPTY-FP (empty fingerprint is a config error, never a distinct ''; reviewer G10)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix ledgeremptyfp "v1${TAB}fpA" "v1${TAB}  ")"
expect_v 2 ERROR NOT_EVALUATED "LEDGER-EMPTY-ID (empty version id with a fingerprint is malformed)" \
    bash "$GATE" --config "$(EXTRA_CONF="$OTHER" mkfix ledgeremptyid "  ${TAB}fpA")"
# config-file errors (M-1): a NAMED config that cannot be read is an error, never a SKIP.
expect_v 2 ERROR NOT_EVALUATED "CONF-MISSING (--config names a file that does not exist)" \
    bash "$GATE" --config "$TMP/no_such_config"
expect_msg 2 "does not exist" "CONF-MISSING-REASON (the existence check names the missing file, not a downstream failure)" \
    bash "$GATE" --config "$TMP/no_such_config"
mkdir -p "$TMP/confdir"
expect_v 2 ERROR NOT_EVALUATED "CONF-DIR (--config names a directory)" \
    bash "$GATE" --config "$TMP/confdir"
expect_v 2 ERROR NOT_EVALUATED "CONF-ENV-MISSING (\$CM_VERSION_DEPLOY_CONFIG names a missing file)" \
    env CM_VERSION_DEPLOY_CONFIG="$TMP/no_such_env_config" bash "$GATE"
unreadable="$(EXTRA_CONF="$PD" mkfix unreadable "1.0.0-dev-0.1.0${TAB}fpA")"; chmod 000 "$unreadable"
if [ -r "$unreadable" ]; then
    note "⏭ META SKIP: CONF-UNREADABLE — running with privileges that read mode-000 files; cannot construct the fixture (§11.4.3)"
else
    expect_msg 2 "is not readable" "CONF-UNREADABLE (mode-000 config, refused by the readability check itself)" bash "$GATE" --config "$unreadable"
fi
chmod 600 "$unreadable"
expect_v 2 ERROR NOT_EVALUATED "CONF-UNKNOWN-KEY (typo 'deploy_leger' must not silently unbind; reviewer M-1)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
deploy_leger = other.tsv" mkfix unknownkey "1.0.0-dev-0.1.0${TAB}fpA")"
expect_v 2 ERROR NOT_EVALUATED "CONF-NOT-KV (a non-comment line that is not key = value)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
just some words" mkfix notkv "1.0.0-dev-0.1.0${TAB}fpA")"
expect_v 2 ERROR NOT_EVALUATED "CONF-EMPTY-VALUE ('version_scheme =' with no value is ambiguous)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme =" mkfix emptyval "1.0.0-dev-0.1.0${TAB}fpA")"
mkdir -p "$TMP/ledgerdir/deploys.d"; printf '%s\n' "deploy_ledger = deploys.d" "$PD" > "$TMP/ledgerdir/config"
expect_v 2 ERROR NOT_EVALUATED "LEDGER-IS-DIR (deploy_ledger names a directory)" \
    bash "$GATE" --config "$TMP/ledgerdir/config"
expect_v 2 ERROR NOT_EVALUATED "DUP-LEDGER-KEY (deploy_ledger declared twice; reviewer G1)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
deploy_ledger = deploys.tsv" mkfix dupledger "1.0.0-dev-0.1.0${TAB}fpA")"
expect_v 2 ERROR NOT_EVALUATED "DUP-MARKER-KEY (carry_adoption_marker declared twice; reviewer G1)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK
$MK" mkfix dupmarker "# decimal-carry adopted" "1.0.0-dev-0.1.0${TAB}fpA")"
# marker scope (M-2 / G9).
expect_v 0 PASS SKIP "MARKER-NO-ROWS-AFTER (marker declared and present, no row after it -> CARRY SKIP, never a PASS on an empty set; reviewer M-2)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix marknorows "1.0.0-dev-0.0.10${TAB}fpA" "# decimal-carry adopted")"
expect_v 2 ERROR NOT_EVALUATED "MARKER-ABSENT-SEMVER (declared marker absent -> exit 2 whatever the scheme; reviewer M-2)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme = semver
${REF}
$MK" mkfix markabsentsemver "1.2.10${TAB}fpA")"
expect_v 0 PASS PASS "NEG-CTRL-MARKER-SUPERSTRING (a line that merely CONTAINS the marker text is not the fence; exact match only; reviewer G9)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
$MK" mkfix marksuper "1.0.0-dev-0.0.10${TAB}fpA" "# decimal-carry adopted (draft, not yet in force)" "1.0.0-dev-0.0.11${TAB}fpB" "# decimal-carry adopted" "1.0.0-dev-0.1.0${TAB}fpC")"
expect_v 0 PASS PASS "NEG-CTRL-MARKER-IS-FULL-ROW (the fence line is itself a valid deploy row 1.0.0-dev-0.0.10<TAB>fpM: it counts for collisions but is never carry-checked)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
carry_adoption_marker = 1.0.0-dev-0.0.10${TAB}fpM" mkfix markfullrow "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.0.10${TAB}fpM" "1.0.0-dev-0.1.0${TAB}fpB")"
expect_v 2 ERROR NOT_EVALUATED "MARKER-FIRST-ONLY (only the FIRST exact marker line is the fence; a later copy of a non-row marker is a malformed row)" \
    bash "$GATE" --config "$(EXTRA_CONF="$PD
carry_adoption_marker = 1.0.0-dev-0.0.10" mkfix markfirst "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.0.10" "1.0.0-dev-0.1.0${TAB}fpB" "1.0.0-dev-0.0.10")"
# exemption record (M-9): a non-positional scheme needs its operator-decision reference.
expect_v 3 UNDECLARED NOT_EVALUATED "UNDECLARED-NO-DECISION-REF (version_scheme = semver without scheme_decision_ref -> UNDECLARED; reviewer M-9)" \
    bash "$GATE" --config "$(EXTRA_CONF="version_scheme = semver" mkfix noref "1.2.10${TAB}fpA")"
# CLI modes (M-2): informational modes only when alone, never a VERDICT line.
helpout="$(bash "$GATE" --help 2>/dev/null)" || true
if grep -q 'CM-VERSION-INCREMENT-ON-DEPLOY gate' <<<"$helpout" && ! grep -qE 'set -euo pipefail|^GATE=|verdict\(\)' <<<"$helpout"; then
    note "✅ META OK:   HELP-HEADER-ONLY (--help prints the header comment block and no code)"
else
    note "❌ META FAIL: HELP-HEADER-ONLY (--help output missing the header or leaking code lines)"; rc=1
fi
expect_info "HELP-ALONE (--help alone: exit 0, no VERDICT line)" bash "$GATE" --help
expect_v 2 ERROR NOT_EVALUATED "HELP-NOT-ALONE (--help combined with --config is refused)" \
    bash "$GATE" --config "$TMP/no_such_config" --help
expect_info "EXAMPLE-NO-VERDICT (--print-example-config alone: exit 0, no VERDICT line)" bash "$GATE" --print-example-config
expect_v 2 ERROR NOT_EVALUATED "EXAMPLE-NOT-ALONE (--print-example-config combined with another argument is refused)" \
    bash "$GATE" --print-example-config --config "$TMP/no_such_config"
mkdir -p "$TMP/example"; bash "$GATE" --print-example-config > "$TMP/example/config" 2>/dev/null
printf '%s\n' "1.0.0-dev-0.0.9${TAB}fpA" "1.0.0-dev-0.1.0${TAB}fpB" > "$TMP/example/deploys.tsv"
expect_v 0 PASS PASS "EXAMPLE-THROUGH-GATE (the documented example config, commented marker line included, is a valid config; reviewer G5)" \
    bash "$GATE" --config "$TMP/example/config"

# Honest note (§11.4.6, round 4): dropping the gate's `export LC_ALL=C` is an
# equivalent mutant on this host — gawk 5.1 interprets [0-9] as ASCII bytes
# (rational range interpretation) under en_US.UTF-8 too; measured with Arabic-
# Indic and fullwidth digits, original and mutant gave the same verdicts. The
# export stays as defense in depth for other awks. Such ids are treated as
# non-digits (opaque) by the gate and refused by the version tool.
# Honest note (§11.4.6): reviewer mutant M5 was classified by the round-2
# review itself as near-equivalent — no behavioural fixture distinguishes it
# from the original; it is recorded here, not claimed "killed".
echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-VERSION-INCREMENT-ON-DEPLOY is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-VERSION-INCREMENT-ON-DEPLOY failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
