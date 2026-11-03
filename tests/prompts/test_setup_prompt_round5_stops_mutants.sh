#!/usr/bin/env bash
# test_setup_prompt_round5_stops_mutants.sh — paired mutation proof (§1.1) for
# test_setup_prompt_round5_stops.sh. For EVERY row of its SITES table this turns that one
# STOP site off in a sandbox copy of latest.md (`exit 3` -> `true`, `return 1` -> `return 0`
# on that line of that block only) and requires the row's scenario to FAIL (the mutant is
# KILLED). Helper copies outside STEP5 are mutated too and must be killed by the IDENTITY check.
# A row whose mutant survives is reported with its id; the suite fails.
# Env: R5M_ONLY=<row id> (one row). Writes only inside a mktemp -d sandbox.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T="$REPO/tests/prompts/test_setup_prompt_round5_stops.sh"
LATEST="$REPO/docs/prompts/setup/latest.md"
W="$(mk_sandbox)"
rows="$(R5_DUMP=1 bash "$T")"
[ "$(wc -l <<<"$rows")" -ge 60 ] && ok "control: $(wc -l <<<"$rows") site rows read" || no "control: only $(wc -l <<<"$rows") rows read (BLIND)"

mutate() { # <block> <key> <from> <to> <out> -> rc 0 when exactly one line changed
  python3 -I - "$LATEST" "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys
src, blk, key, frm, to, out = sys.argv[1:]
ls = open(src, encoding='utf-8').read().split('\n')
inb = False; hits = []
for i, l in enumerate(ls):
    if l.strip() == '# %s-BEGIN' % blk: inb = True; continue
    if l.strip() == '# %s-END' % blk: inb = False; continue
    if inb and key in l and frm in l: hits.append(i)
if len(hits) != 1:
    sys.stderr.write('mutation target count %d\n' % len(hits)); sys.exit(1)
ls[hits[0]] = ls[hits[0]].replace(frm, to)
open(out, 'w', encoding='utf-8').write('\n'.join(ls))
PY
}
killed=0; survived=0; surv=""
while IFS='|' read -r id blk key _ _ scen want marker; do
  [ -n "$id" ] || continue
  [ -z "${R5M_ONLY:-}" ] || [ "$id" = "$R5M_ONLY" ] || continue
  key="${key//@@/|}"; frm='exit 3'; to='true'
  case "$id" in S5-OC-*|S5-UNP-NOREMOTE|S5-GMCRED-NONE) frm='return 1'; to='return 0' ;; esac
  m="$W/$id.md"
  if ! mutate "$blk" "$key" "$frm" "$to" "$m" 2>"$W/$id.err"; then no "$id: could not place the mutant ($(cat "$W/$id.err"))"; continue; fi
  if R5_LATEST="$m" R5_ONLY="$id" bash "$T" >"$W/$id.out" 2>&1; then
    survived=$((survived + 1)); surv="$surv $id"; no "MUTANT SURVIVED $id ($blk: $frm -> $to)"
  else
    killed=$((killed + 1)); ok "killed $id"
  fi
done <<<"$rows"
# Non-canonical helper copies: turn a refusal off in each copy; the IDENTITY check must FAIL.
if [ -z "${R5M_ONLY:-}" ]; then
  for spec in "STEP2|is another repository: its git dir|return 1|return 0" \
              "STEP3|is a worktree of the parent project|return 1|return 0" \
              "STEP4|[ \"\$ok\" = 1 ] @@@@ return 1|return 1|return 0" \
              "STEP2|done < <(git config -f .gitmodules --get-regexp|return 1|return 0" \
              "STEP3|credrx='|@|@@" \
              "STEP4|redact() {|g'|'"; do
    IFS='|' read -r blk key frm to <<<"$spec"; key="${key//@@/|}"
    m="$W/h_${blk}_$RANDOM.md"
    if ! mutate "$blk" "$key" "$frm" "$to" "$m" 2>/dev/null; then no "helper mutant not placed: $spec"; continue; fi
    if R5_LATEST="$m" R5_NOSCEN=1 bash "$T" >"$m.out" 2>&1; then
      survived=$((survived + 1)); surv="$surv H:$blk:$key"; no "MUTANT SURVIVED helper copy $blk ($key)"
    else killed=$((killed + 1)); ok "killed helper copy mutant $blk ($key)"; fi
  done
fi
echo "MUTANTS killed=$killed survived=$survived${surv:+ (survivors:$surv)}"
summary round5_stops_mutants
