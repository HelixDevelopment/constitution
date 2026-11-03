#!/usr/bin/env bash
# cm_installer_script_modes_mutation_test.sh — §1.1 paired-mutation meta-test for CM-INSTALLER-SCRIPT-MODES.
#
# Fixture repositories (scratch git repos built here; the real repository is never touched):
#   golden   every scoped shebang script executable/100755, plus a shebang-less fragment at 0644 → PASS (0)
#   F1       an UNTRACKED scoped script at 0644                                            → FAIL (1)
#   F2       a TRACKED scoped script recorded 100644 (working tree 0755: only the index counts) → FAIL (1)
#   F3       nothing in scope                                                              → BLIND (2)
#   F4       golden-FALSE: only the shebang-less fragment is 0644                           → PASS (0)
#   F5       hook-chmod scope: a scripts/*.sh direct child at 0644                          → FAIL (1)
# Gate mutants (applied to a scratch COPY of the gate) must not PASS the golden-bad fixture F1:
#   K1 the shebang test removed    K2 the index mode ignored (worktree -x only)    K3 the untracked branch always PASS
# Usage: cm_installer_script_modes_mutation_test.sh   Exit 0 proof holds · 1 misclassified/survivor · 2 env error.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; gate="$here/cm_installer_script_modes.sh"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_modes_meta.XXXXXX")" || exit 2
# shellcheck source=../lib/safe_rm.sh
. "$here/../lib/safe_rm.sh"
trap 'SAFE_RM_ALLOWED_ROOTS="$tmp" safe_rm_rf "${tmp:?}"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CEILING_DIRECTORIES="$tmp"
printf '[user]\n\tname = meta\n\temail = m@example.invalid\n' >"$GIT_CONFIG_GLOBAL"
bad=0
mkrepo() { # dir → golden repository (tracked + untracked scoped scripts, all executable)
  local d="$1"
  mkdir -p "$d/scripts/gates" "$d/tests/install" && git -C "$d" init -q || return 1
  printf '#!/usr/bin/env bash\n' >"$d/scripts/install_constitution.sh"
  printf '#!/usr/bin/env bash\n' >"$d/scripts/update_constitution.sh"
  printf '#!/usr/bin/env bash\n' >"$d/scripts/gates/cm_installer_x.sh"
  printf '#!/usr/bin/env bash\n' >"$d/tests/install/test_a.sh"
  printf 'x=1   # fragment, no shebang\n' >"$d/tests/install/frag.sh"
  chmod 755 "$d/scripts/install_constitution.sh" "$d/scripts/update_constitution.sh" "$d/scripts/gates/cm_installer_x.sh" "$d/tests/install/test_a.sh"
  chmod 644 "$d/tests/install/frag.sh"
  git -C "$d" add -- scripts/update_constitution.sh tests/install/test_a.sh && git -C "$d" commit -qm golden
}
expect() { # name want-rc gate root [scope]
  local out rc; out="$(bash "$3" --root "$4" ${5:+--scope "$5"} 2>&1)"; rc=$?
  if [ "$rc" = "$2" ]; then echo "  ok   $1 (rc=$rc)"; else echo "  FAIL $1 (want rc=$2 got $rc): $(printf '%s' "$out" | tail -n 1)"; bad=$((bad+1)); fi
}
mkrepo "$tmp/golden" || { echo "META: fixture failed" >&2; exit 2; }
expect "golden: every scoped script executable -> PASS" 0 "$gate" "$tmp/golden"
mkrepo "$tmp/f1" && chmod 644 "$tmp/f1/scripts/install_constitution.sh"
expect "F1 untracked scoped script 0644 -> FAIL" 1 "$gate" "$tmp/f1"
mkrepo "$tmp/f2" && git -C "$tmp/f2" update-index --chmod=-x tests/install/test_a.sh && git -C "$tmp/f2" commit -qm 644
check_wt="$(stat -c %a "$tmp/f2/tests/install/test_a.sh")"
[ "$check_wt" = 755 ] || { echo "  FAIL F2 precondition: worktree mode $check_wt (want 755)"; bad=$((bad+1)); }
expect "F2 tracked 100644 (worktree 0755) -> FAIL" 1 "$gate" "$tmp/f2"
mkdir -p "$tmp/f3/docs" && git -C "$tmp/f3" init -q && printf '#!/bin/sh\n' >"$tmp/f3/docs/x.sh"
expect "F3 nothing in scope -> BLIND" 2 "$gate" "$tmp/f3"
mkrepo "$tmp/f4"
expect "F4 golden-FALSE: only a shebang-less fragment is 0644 -> PASS" 0 "$gate" "$tmp/f4"
mkrepo "$tmp/f5" && printf '#!/bin/sh\n' >"$tmp/f5/scripts/other.sh" && chmod 644 "$tmp/f5/scripts/other.sh"
expect "F5 hook-chmod scope: scripts/other.sh 0644 -> FAIL" 1 "$gate" "$tmp/f5" hook-chmod
expect "F5 control: the installer scope ignores scripts/other.sh -> PASS" 0 "$gate" "$tmp/f5"
mutant() { # name sed-expression
  local m="$tmp/gate_$1.sh"; sed "$2" "$gate" >"$m"
  if cmp -s "$gate" "$m"; then echo "  FAIL mutant $1 did not apply"; bad=$((bad+1)); return; fi
  local rc; bash "$m" --root "$tmp/f1" >/dev/null 2>&1; rc=$?
  bash "$m" --root "$tmp/f2" >/dev/null 2>&1; local rc2=$?
  if [ "$rc" = 0 ] || [ "$rc2" = 0 ]; then echo "  FAIL mutant $1 SURVIVED (f1 rc=$rc, f2 rc=$rc2)"; bad=$((bad+1))
  else echo "  ok   mutant $1 killed (f1 rc=$rc, f2 rc=$rc2)"; fi
}
mutant K1 "s/\[ \"\$hdr\" = '#!' \] || { printf 'SKIP no-shebang'; return; }/:/"
mutant K2 's/ent="$(git -C "$r" ls-files -s -- "$rel" 2>\/dev\/null | head -n 1)"/ent=""/'
mutant K3 "s/else printf 'FAIL untracked-mode-%s'/else printf 'PASS untracked-mode-%s'/"
[ "$bad" = 0 ] && echo "META PASS: CM-INSTALLER-SCRIPT-MODES classifies every fixture and kills every mutant" || echo "META FAIL: $bad case(s)"
[ "$bad" = 0 ]
