#!/usr/bin/env bash
# cm_installer_truncation_safe_mutation_test.sh — §1.1 paired-mutation meta-test for CM-INSTALLER-TRUNCATION-SAFE.
#
# Golden: the real installer MUST PASS (exit 0).
# Mutants (each applied to a scratch COPY; the real file is never touched) MUST make the gate FAIL (exit 1):
#   M1 sentinel dropped from the last line (`main "$@"`)          — static check (1)
#   M2 main's sentinel check disabled                              — check (2)
#   M3 a top-level statement that does work before main is defined — dynamic check (3)
#   A  sentinel checked (and stripped) only when there is >= 1 argument — zero-argument check (4)
# Usage: cm_installer_truncation_safe_mutation_test.sh   Exit 0 proof holds · 1 misclassified/survivor · 2 env error.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_installer_truncation_safe.sh"; inst="$here/../install_constitution.sh"
[ -r "$gate" ] && [ -r "$inst" ] || { echo "META: gate or installer missing" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_trunc_meta.XXXXXX")" || exit 2
trap 'rm -f -- "${tmp:?}"/*.sh; rmdir -- "${tmp:?}"' EXIT
bad=0
expect() { # name want-rc file
  bash "$gate" --installer "$3" --step 997 >/dev/null 2>&1; local rc=$?
  if [ "$rc" = "$2" ]; then echo "  ok   $1 (rc=$rc)"; else echo "  FAIL $1 (want rc=$2 got $rc)"; bad=$((bad+1)); fi
}
expect "golden real installer PASS" 0 "$inst"
sed '$ s/ __helix_installer_eof__$//' "$inst" >"$tmp/m1.sh"; expect "M1 sentinel dropped -> FAIL" 1 "$tmp/m1.sh"
sed 's/if \[ "\$#" -lt 1 \] || \[ "\${!#}" != "__helix_installer_eof__" \]; then/if false; then/' "$inst" >"$tmp/m2.sh"
cmp -s "$inst" "$tmp/m2.sh" && { echo "  FAIL M2 mutation did not apply"; bad=$((bad+1)); }
expect "M2 sentinel check disabled -> FAIL" 1 "$tmp/m2.sh"
awk '{ print } /^HI_VERSION=/ { print "case \" $* \" in *\" --print-snippets \"*) echo \"curl -fsSL early-work | bash\" ;; esac" }' "$inst" >"$tmp/m3.sh"
cmp -s "$inst" "$tmp/m3.sh" && { echo "  FAIL M3 mutation did not apply"; bad=$((bad+1)); }
expect "M3 top-level work before main -> FAIL" 1 "$tmp/m3.sh"
# The guard alone is not enough to make A dangerous (with no argument `${@:1:-1}` aborts bash), so A also
# guards the argument strip: that is the realistic "only check when arguments were given" regression.
sed -e 's/if \[ "\$#" -lt 1 \] || \[ "\${!#}" != "__helix_installer_eof__" \]; then/if [ "$#" -ge 1 ] \&\& [ "${!#}" != "__helix_installer_eof__" ]; then/' \
    -e 's/^  set -- "\${@:1:\$((\$# - 1))}"$/  [ "$#" -ge 1 ] \&\& set -- "${@:1:$(($# - 1))}"/' "$inst" >"$tmp/ma.sh"
[ "$(diff "$inst" "$tmp/ma.sh" | grep -c '^>')" = 2 ] || { echo "  FAIL A mutation did not apply to both lines"; bad=$((bad+1)); }
cmp -s "$inst" "$tmp/ma.sh" && { echo "  FAIL A mutation did not apply"; bad=$((bad+1)); }
expect "A sentinel check only with >= 1 argument -> FAIL" 1 "$tmp/ma.sh"
[ "$bad" = 0 ] && echo "META PASS: CM-INSTALLER-TRUNCATION-SAFE kills every mutant" || echo "META FAIL: $bad case(s)"
[ "$bad" = 0 ]
