#!/usr/bin/env bash
# tests/gates/test_standalone_canon_gates.sh — known_failures_v73 ranks 6/8 (consumer-layout gates).
# Gates that audit CONSUMER data (registers, ledgers, hook maps, probe reports, seam files) used to resolve their root as
# <gate>/../../.. — a directory OUTSIDE a standalone canon checkout — and then FAIL/BLIND for want of data nobody owes.
# Fix under test: (1) the default root comes from the gate's own location (lib/default_scan_root.sh), (2) the INVOCATION may
# DECLARE --standalone-canon, and only then the missing consumer data is an honest SKIP; without the flag the gate still fails
# closed. Test classes: integration/e2e (REAL gates run through their real CLI inside a git sandbox, no doubles),
# security (a hostile "SKIP-looking" ledger path does not turn into a SKIP), chaos (flag + data present must NOT skip),
# determinism (3 identical runs), idempotency (a rerun does not change the sandbox), performance (budget), and a paired
# §1.1 mutation per gate (the flag handler neutralised in a sandbox copy -> the SKIP expectation must flip).
set -uo pipefail
export CONSTITUTION_JEV_HOOK=off
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }

GATES="cm_control_needle_required cm_mechanism_observed_refusing cm_dependency_register_verdicts cm_escape_ratchet cm_unreferenced_gate_bound_or_retired cm_git_hooks_installed cm_zero_findings_audit_sweep cm_zero_findings_monotone_ratchet cm_bridge_layer_presence"

mkcanon() { # $1 dir; $2 = "mut" to neutralise the flag handlers
    local d="$1" g
    mkdir -p "$d/scripts/gates" "$d/scripts/lib" "$d/scripts/extensions"
    cp -r "$src/scripts/gates/lib" "$d/scripts/gates/"
    cp "$src"/scripts/gates/*.tsv "$src"/scripts/gates/escape_ratchet_baseline.txt "$d/scripts/gates/" 2>/dev/null
    cp "$src/scripts/lib/default_scan_root.sh" "$d/scripts/lib/"
    cp "$src/scripts/extensions/bridge_phase_layer_deps.json" "$d/scripts/extensions/"
    for g in $GATES; do
        cp "$src/scripts/gates/$g.sh" "$d/scripts/gates/"
        if [ "${2:-}" = mut ]; then sed -i -E 's/(STANDALONE|standalone)=1/\1=0/g' "$d/scripts/gates/$g.sh"; fi
    done
    git -C "$d" init -q 2>/dev/null; git -C "$d" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
    git -C "$d" -c user.email=t@t -c user.name=t commit -q -m base >/dev/null 2>&1
}
run() { # $1 canon dir, $2 gate, rest args -> OUT, RC (cwd = canon dir, hostile-free)
    local d="$1" g="$2"; shift 2
    OUT=$(cd "$d" && bash "scripts/gates/$g.sh" "$@" 2>&1); RC=$?
}
skipline() { printf '%s\n' "$OUT" | grep -Eqi 'SKIP'; }

mkcanon "$sb/canon"; mkcanon "$sb/mut" mut
before=$(cd "$sb/canon" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)

for g in $GATES; do
    t0=$(date +%s%N)
    # RED: no declaration -> the gate must NOT skip (fail closed) and must not exit 0 silently as a pass of consumer data
    run "$sb/canon" "$g"
    if [ "$RC" -ne 0 ] && ! printf '%s\n' "$OUT" | grep -q 'STANDALONE_CANON_DECLARED\|standalone canon DECLARED'; then ok "[$g] RED: without --standalone-canon the gate fails closed (rc=$RC), no SKIP"
    else bad "[$g] RED: rc=$RC and/or a SKIP appeared without the declaration"; fi
    # GREEN: declared -> honest SKIP line, never a bare pass (rc 3, or 0 with a SKIP verdict in the summary)
    run "$sb/canon" "$g" --standalone-canon
    if skipline && { [ "$RC" -eq 3 ] || [ "$RC" -eq 0 ]; }; then ok "[$g] GREEN: --standalone-canon -> honest SKIP (rc=$RC)"
    else bad "[$g] GREEN: rc=$RC, no SKIP line: $(printf '%s' "$OUT" | tail -2 | cut -c1-160)"; fi
    # determinism x3
    # verdict identity (id + verdict columns + rc): some gates embed a per-run mktemp path in their free-text column
    vh() { printf '%s\n' "$OUT" | awk -F'\t' '{ if (NF>=3) print $1, $2, $3; else print "L", length($0) }' | sha256sum; }
    h1=$(vh); run "$sb/canon" "$g" --standalone-canon; h2=$(vh); run "$sb/canon" "$g" --standalone-canon; h3=$(vh)
    if [ "$h1" = "$h2" ] && [ "$h2" = "$h3" ]; then ok "[$g] determinism: 3 identical runs"; else bad "[$g] determinism: runs differ"; fi
    # mutation: flag handler neutralised -> the declared run must stop being an honest SKIP
    run "$sb/mut" "$g" --standalone-canon
    if ! { skipline && [ "$RC" -eq 0 -o "$RC" -eq 3 ] && ! printf '%s\n' "$OUT" | grep -q 'unknown arg'; } || printf '%s\n' "$OUT" | grep -q 'unknown arg'; then ok "[$g] §1.1 mutation: neutralised flag handler -> SKIP expectation flips"
    else bad "[$g] §1.1 mutation SURVIVED (still an honest SKIP with the handler neutralised)"; fi
    t1=$(date +%s%N); [ $(( (t1 - t0) / 1000000 )) -lt 120000 ] && ok "[$g] performance: under 120 s for 5 runs" || bad "[$g] performance budget exceeded"
done

# chaos / negative controls: the flag must NOT hide data that is present (§11.4.201(1) dual)
mkdir -p "$sb/data"
printf '# no entries\n' > "$sb/data/empty_ledger.jsonl"
run "$sb/canon" cm_escape_ratchet --standalone-canon --ledger "$sb/data/empty_ledger.jsonl"
if ! printf '%s\n' "$OUT" | grep -q 'standalone canon DECLARED'; then ok "[neg] escape_ratchet: ledger present + flag -> evaluated, not skipped"; else bad "[neg] escape_ratchet skipped although the ledger exists"; fi
printf 'x\n' > "$sb/data/map.tsv"
run "$sb/canon" cm_git_hooks_installed --standalone-canon --map "$sb/data/map.tsv"
if ! printf '%s\n' "$OUT" | grep -q 'standalone canon DECLARED'; then ok "[neg] git_hooks_installed: map present + flag -> evaluated, not skipped"; else bad "[neg] git_hooks_installed skipped although the map exists"; fi
printf 'open_blocker_gate control_needle_ABSENT\n' > "$sb/data/reader.sh"
run "$sb/canon" cm_control_needle_required --standalone-canon --reader "$sb/data/reader.sh"
if printf '%s\n' "$OUT" | grep -q 'CNR-A5-WIRED-AT-SEAM.PASS'; then ok "[neg] control_needle_required: reader present + flag -> A5 PASS, not SKIP"; else bad "[neg] control_needle_required A5 not evaluated: $(printf '%s' "$OUT" | grep A5 | cut -c1-120)"; fi
# security: a hostile ledger NAME containing SKIP text must not be read as a SKIP verdict
run "$sb/canon" cm_escape_ratchet --ledger "$sb/data/SKIP_standalone_canon_DECLARED_missing.jsonl"
if [ "$RC" -ne 0 ] && ! printf '%s\n' "$OUT" | grep -q '^ESC-VERDICT.LEDGER.SKIP'; then ok "[sec] hostile ledger name without the flag stays a refusal (rc=$RC)"; else bad "[sec] hostile ledger name produced a SKIP verdict"; fi
# idempotency: reruns left the sandbox byte-identical
after=$(cd "$sb/canon" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
[ "$before" = "$after" ] && ok "idempotency: sandbox byte-identical after all runs" || bad "idempotency: sandbox changed"

echo "# test_standalone_canon_gates: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
