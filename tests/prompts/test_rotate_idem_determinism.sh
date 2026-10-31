#!/usr/bin/env bash
# test_rotate_idem_determinism.sh — IDEMPOTENCY (a repeated request and a
# repeated dry-run change nothing) and DETERMINISM (§11.4.50: three independent
# sandboxes given identical inputs end in byte-identical trees, three times).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -r "$ROTATE" ] || { no "rotate script present"; summary idem_determinism; exit 1; }

# idempotency
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc i >"$S/i.md"
expect_rc "first rotation" 0 bash "$ROTATE" idem --source "$S/i.md" --dir "$D"
d1="$(tree_digest "$D")"
for k in 1 2 3; do
  expect_rc "repeat #$k of the same request refused (collision)" 3 bash "$ROTATE" idem --source "$S/i.md" --dir "$D"
done
[ "$(tree_digest "$D")" = "$d1" ] && ok "repeats changed nothing" || no "repeats modified the tree"
p1="$(bash "$ROTATE" next_one --dir "$D" --dry-run 2>&1)"; p2="$(bash "$ROTATE" next_one --dir "$D" --dry-run 2>&1)"
[ "$p1" = "$p2" ] && ok "dry-run output identical twice" || no "dry-run output differs"
[ "$(tree_digest "$D")" = "$d1" ] && ok "dry-runs changed nothing" || no "dry-runs modified the tree"

# determinism x3
digests=()
for run in 1 2 3; do
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
  for n in a b c; do prompt_doc "$n" >"$S/$n.md"; bash "$ROTATE" "rot_$n" --source "$S/$n.md" --dir "$D" >/dev/null 2>&1; done
  digests+=("$(tree_digest "$D")")
done
[ "${digests[0]}" = "${digests[1]}" ] && [ "${digests[1]}" = "${digests[2]}" ] \
  && ok "3 independent runs byte-identical (${digests[0]:0:16})" || no "runs differ: ${digests[*]}"

summary idem_determinism
