#!/usr/bin/env bash
# cm_release_tag_carry_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-RELEASE-TAG-CARRY (§11.4.151 decimal-carry clause, §11.4.235(E.5)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuine with golden-good / golden-bad / negative-control
# fixtures, in both modes (tag list file and a real throwaway git repository):
#   MUST FAIL (exit 1, VERDICT: FAIL): `p-1.0.0-dev-0.0.10` (the operator's own
#     wrong tag), a 2-digit middle position, a 2-digit release-id position
#     (`p-1.0.10`), a leftmost leading zero, a dash-joined numeric pair, and a
#     bad tag hidden among good ones (and in a real git repo).
#   MUST PASS (exit 0, VERDICT: PASS): the carried successor `-0.1.0`, the full
#     ladder 0.0.8 0.0.9 0.1.0, `-0.9.9 -> -1.0.0`, a growing LEFTMOST position
#     (`p-10.0.0`), a non-numeric suffix (`-rc1`), and a foreign-prefix tag with
#     a no-carry shape (not this project's tag, ignored — §11.4.201(1) guard).
#   SKIP (exit 4): no prefixed tag; declared exemption with decision ref.
#   ERROR (exit 2): no prefix, missing input, both inputs, unknown flag.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_release_tag_carry_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir (trap-cleaned). No network, no commit
#   outside the throwaway repository.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, git, the sibling cm_release_tag_carry.sh. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1, §11.4.151, §11.4.235(E.5), §11.4.201(1), §11.4.107(10).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 every case behaved exactly as required · 1 a case misbehaved · 2 env error.
#
# Classification: universal (§11.4.17).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/cm_release_tag_carry.sh"
[ -x "$GATE" ] || { echo "META: gate not found/executable: $GATE" >&2; exit 2; }
command -v git >/dev/null || { echo "META: git missing" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0

run() { # run <name> <want_rc> <want_verdict> <args...>
    local name="$1" wrc="$2" wv="$3"; shift 3
    local out rc; out="$("$GATE" "$@" 2>&1)"; rc=$?; n=$((n+1))
    if [ "$rc" -ne "$wrc" ] || ! printf '%s\n' "$out" | grep -qx "VERDICT: $wv"; then
        echo "META FAIL: $name: rc=$rc (want $wrc) verdict-want=$wv"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
    else echo "META ok  : $name (rc=$rc, $wv)"; fi
}
tf() { printf '%s\n' "${@:2}" > "$T/$1.tags"; }

tf bad_00_10   p-1.0.0-dev-0.0.8 p-1.0.0-dev-0.0.9 p-1.0.0-dev-0.0.10
tf bad_mid     p-1.0.0-dev-0.10.0
tf bad_rel     p-1.0.10
tf bad_lead0   p-01.0.0
tf bad_dash    p-1.0.0-dev-0.0-9
tf bad_hidden  p-1.0.0-dev-0.0.1 p-1.0.0-dev-0.0.2 p-1.0.0-dev-0.0.10 p-1.0.0-dev-0.0.3
tf good_carry  p-1.0.0-dev-0.1.0
tf good_ladder p-1.0.0-dev-0.0.8 p-1.0.0-dev-0.0.9 p-1.0.0-dev-0.1.0
tf good_99     p-1.0.0-dev-0.9.9 p-1.0.0-dev-1.0.0
tf good_left   p-10.0.0
tf good_rc     p-1.0.0-rc1
tf foreign     other-1.0.0-dev-0.0.10 p-1.0.0-dev-0.1.0
tf none        other-1.0.0-dev-0.0.1
tf digit_prefix v2-1.0.0-dev-0.1.0
tf bad_dotted_suffix p-1.0.0-dev-0.0.9-rc.1.12
tf comments    '# comment' '' p-1.0.0-dev-0.0.9

for c in bad_dotted_suffix bad_00_10 bad_mid bad_rel bad_lead0 bad_dash bad_hidden; do run "MUST-FAIL $c" 1 FAIL --prefix p --tags-file "$T/$c.tags"; done
for c in good_carry good_ladder good_99 good_left good_rc foreign comments; do run "MUST-PASS $c" 0 PASS --prefix p --tags-file "$T/$c.tags"; done
run "MUST-PASS digit-ending prefix (no false dash-join)" 0 PASS --prefix v2 --tags-file "$T/digit_prefix.tags"
run "SKIP no prefixed tag" 4 SKIP --prefix p --tags-file "$T/none.tags"
run "SKIP declared exemption" 4 SKIP --prefix p --tags-file "$T/bad_00_10.tags" --exempt-decision-ref OD-1
run "ERROR no prefix" 2 ERROR --tags-file "$T/good_carry.tags"
run "ERROR no input" 2 ERROR --prefix p
run "ERROR both inputs" 2 ERROR --prefix p --repo "$T" --tags-file "$T/good_carry.tags"
run "ERROR missing file" 2 ERROR --prefix p --tags-file "$T/nope"
run "ERROR not a dir" 2 ERROR --prefix p --repo "$T/nope"
run "ERROR unknown flag" 2 ERROR --prefix p --frobnicate
run "ERROR bad prefix chars" 2 ERROR --prefix 'p;x' --tags-file "$T/good_carry.tags"

# real git repository mode
R="$T/repo"; git init -q "$R" && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c || { echo "META: git fixture failed" >&2; exit 2; }
for t in p-1.0.0-dev-0.0.9 p-1.0.0-dev-0.1.0; do git -C "$R" tag "$t"; done
run "REPO MUST-PASS carried ladder" 0 PASS --prefix p --repo "$R"
git -C "$R" tag p-1.0.0-dev-0.0.10
run "REPO MUST-FAIL after wrong tag" 1 FAIL --prefix p --repo "$R"
HELIX_RELEASE_PREFIX=p run "ENV prefix honoured (FAIL)" 1 FAIL --repo "$R"

echo "META: $n cases, $([ $fail -eq 0 ] && echo ALL PASS || echo FAILURES)"
exit $fail
